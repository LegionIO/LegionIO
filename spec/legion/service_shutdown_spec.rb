# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe Legion::Service do
  let(:service) { described_class.allocate }

  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:warn)
    allow(Legion::Logging).to receive(:error)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:emit_tagged) do |level, msg, **|
      Legion::Logging.public_send(level, msg) if Legion::Logging.respond_to?(level)
    end
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Settings).to receive(:[]).with(:client).and_return({ ready: true, shutting_down: false })
    allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: false })
    allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ connected: false })
    allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: false })
    allow(Legion::Settings).to receive(:[]).with(:llm).and_return(nil)
    allow(Legion::Settings).to receive(:[]).with(:rbac).and_return(nil)
    allow(Legion::Settings).to receive(:[]).with(:network).and_return(nil)
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:extensions, :shutdown_timeout).and_return(nil)
  end

  describe '#shutdown_component' do
    it 'executes the block normally when it completes in time' do
      executed = false
      service.shutdown_component('Test') { executed = true }
      expect(executed).to be true
    end

    it 'does not raise when the block times out' do
      expect do
        service.shutdown_component('Test', timeout: 0.1) { sleep 5 }
      end.not_to raise_error
    end

    it 'logs a warning when the block times out' do
      service.shutdown_component('Test', timeout: 0.1) { sleep 5 }
      expect(Legion::Logging).to have_received(:warn).with(/Test shutdown timed out/)
    end

    it 'completes within the timeout even if the block hangs' do
      start = Time.now
      service.shutdown_component('Test', timeout: 0.5) { sleep 60 }
      elapsed = Time.now - start
      expect(elapsed).to be < 2.0
    end

    it 'rescues StandardError from the block' do
      expect do
        service.shutdown_component('Test') { raise 'boom' }
      end.not_to raise_error
    end

    it 'logs a warning on StandardError' do
      allow(service).to receive(:handle_exception)
      service.shutdown_component('Test') { raise 'boom' }
      expect(service).to have_received(:handle_exception).with(
        instance_of(RuntimeError),
        level:     :warn,
        operation: 'service.shutdown_component',
        component: 'Test',
        timeout:   5
      )
    end
  end

  describe '#shutdown' do
    before do
      allow(service).to receive(:shutdown_network_watchdog)
      allow(service).to receive(:shutdown_audit_archiver)
      allow(service).to receive(:shutdown_api)
      allow(service).to receive(:shutdown_mtls_rotation)
      allow(Legion::Readiness).to receive(:mark_not_ready)

      # Stub identity broker shutdown to avoid leaked-double errors
      broker_mod = Module.new
      stub_const('Legion::Identity::Broker', broker_mod)
      allow(broker_mod).to receive(:shutdown)

      # Stub extensions shutdown
      allow(Legion::Extensions).to receive(:shutdown).and_return(true)

      # Stub cache shutdown
      cache_mod = Module.new
      stub_const('Legion::Cache', cache_mod)
      allow(cache_mod).to receive(:shutdown)

      # Stub transport shutdown
      transport_conn = Module.new
      stub_const('Legion::Transport::Connection', transport_conn)
      allow(transport_conn).to receive(:shutdown)

      # Stub crypt shutdown
      crypt_mod = Module.new
      stub_const('Legion::Crypt', crypt_mod)
      allow(crypt_mod).to receive(:shutdown)
    end

    it 'shuts down the network watchdog first' do
      service.shutdown
      expect(service).to have_received(:shutdown_network_watchdog)
    end

    it 'does not close dependencies when actor shutdown fails' do
      allow(Legion::Extensions).to receive(:shutdown).and_raise(IOError, 'consumer cancellation failed')

      expect { service.shutdown }.to raise_error(IOError, 'consumer cancellation failed')

      expect(Legion::Cache).not_to have_received(:shutdown)
      expect(Legion::Transport::Connection).not_to have_received(:shutdown)
      expect(Legion::Crypt).not_to have_received(:shutdown)
    end

    it 'retains dependencies when actors report an incomplete drain' do
      allow(Legion::Extensions).to receive(:shutdown).and_return(false)

      expect(service.shutdown).to be false

      expect(Legion::Cache).not_to have_received(:shutdown)
      expect(Legion::Transport::Connection).not_to have_received(:shutdown)
      expect(Legion::Crypt).not_to have_received(:shutdown)
      expect(Legion::Readiness).not_to have_received(:mark_not_ready).with(:extensions)
    end

    it 'waits for actor completion before closing shared dependencies' do
      entered = Concurrent::Event.new
      release = Concurrent::Event.new
      allow(Legion::Extensions).to receive(:shutdown) do
        entered.set
        release.wait
        true
      end
      thread = Thread.new { service.shutdown }
      expect(entered.wait(2)).to be true

      expect(Legion::Cache).not_to have_received(:shutdown)
      expect(Legion::Transport::Connection).not_to have_received(:shutdown)
      release.set
      thread.join(2)

      expect(thread.alive?).to be false
      expect(Legion::Cache).to have_received(:shutdown)
      expect(Legion::Transport::Connection).to have_received(:shutdown)
      expect(Legion::Crypt).to have_received(:shutdown)
    ensure
      release&.set
      thread&.join(2)
    end
  end

  describe '#setup_network_watchdog' do
    it 'does nothing when watchdog is not enabled' do
      allow(Legion::Settings).to receive(:dig).with(:network, :watchdog, :enabled).and_return(nil)

      service.setup_network_watchdog
      expect(service.instance_variable_get(:@network_watchdog)).to be_nil
    end

    it 'creates a timer task when enabled' do
      allow(Legion::Settings).to receive(:dig).with(:network, :watchdog, :enabled).and_return(true)
      allow(Legion::Settings).to receive(:dig).with(:network, :watchdog, :failure_threshold).and_return(3)
      allow(Legion::Settings).to receive(:dig).with(:network, :watchdog, :check_interval).and_return(60)
      allow(service).to receive(:network_healthy?).and_return(true)

      service.setup_network_watchdog
      watchdog = service.instance_variable_get(:@network_watchdog)
      expect(watchdog).to be_a(Concurrent::TimerTask)

      # Clean up
      watchdog.shutdown
    end
  end

  describe '#shutdown_network_watchdog' do
    it 'shuts down the watchdog timer if running' do
      timer = instance_double(Concurrent::TimerTask)
      allow(timer).to receive(:shutdown)
      service.instance_variable_set(:@network_watchdog, timer)

      service.shutdown_network_watchdog

      expect(timer).to have_received(:shutdown)
      expect(service.instance_variable_get(:@network_watchdog)).to be_nil
    end

    it 'does nothing when no watchdog is running' do
      expect { service.shutdown_network_watchdog }.not_to raise_error
    end
  end

  describe '#network_healthy?' do
    before do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: false })
      allow(Legion::Settings).to receive(:[]).with(:data).and_return({ connected: false })
      allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ connected: false })
    end

    it 'returns true in lite mode' do
      transport_conn = Module.new
      stub_const('Legion::Transport::Connection', transport_conn)
      allow(transport_conn).to receive(:lite_mode?).and_return(true)

      expect(service.network_healthy?).to be true
    end

    it 'returns true when no backends are configured for checking' do
      expect(service.network_healthy?).to be true
    end

    it 'returns true when transport is connected and session is open' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
      transport_conn = Module.new
      stub_const('Legion::Transport::Connection', transport_conn)
      allow(transport_conn).to receive(:lite_mode?).and_return(false)
      allow(transport_conn).to receive(:session_open?).and_return(true)

      expect(service.network_healthy?).to be true
    end

    it 'returns false on exception' do
      allow(Legion::Settings).to receive(:[]).with(:transport).and_raise(StandardError, 'gone')

      expect(service.network_healthy?).to be false
    end
  end
end
