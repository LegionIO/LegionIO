# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Service#setup_logging_transport' do
  let(:service) { Legion::Service.allocate }

  before do
    Legion::Logging.log_writer = nil
    Legion::Logging.exception_writer = nil
  end

  after do
    Legion::Logging.log_writer = nil
    Legion::Logging.exception_writer = nil
  end

  context 'when transport is not connected' do
    it 'returns early without wiring writers' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(false)
      allow(Legion::Transport::Connection).to receive(:create_dedicated_session)
      service.send(:setup_logging_transport)
      expect(Legion::Transport::Connection).not_to have_received(:create_dedicated_session)
      expect(service.instance_variable_get(:@log_session)).to be_nil
    end
  end

  context 'when transport.enabled is false' do
    it 'returns early without wiring writers' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(true)
      allow(Legion::Settings).to receive(:dig).with(:logging, :transport).and_return({ enabled: false })
      allow(Legion::Transport::Connection).to receive(:create_dedicated_session)
      service.send(:setup_logging_transport)
      expect(Legion::Transport::Connection).not_to have_received(:create_dedicated_session)
      expect(service.instance_variable_get(:@log_session)).to be_nil
    end
  end

  context 'when transport.enabled is true and both flags are false' do
    it 'returns early without creating a session' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(true)
      allow(Legion::Settings).to receive(:dig).with(:logging, :transport)
                                              .and_return({ enabled: true, forward_logs: false, forward_exceptions: false })
      service.send(:setup_logging_transport)
      expect(service.instance_variable_get(:@log_session)).to be_nil
    end
  end

  context 'when transport.enabled is true with defaults' do
    let(:mock_channel) { double('channel', open?: true, prefetch: nil) }
    let(:mock_exchange) { double('exchange') }
    let(:mock_session)  { double('session', create_channel: mock_channel) }

    before do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(true)
      allow(Legion::Settings).to receive(:dig).with(:logging, :transport).and_return({ enabled: true })
      allow(Legion::Transport::Connection).to receive(:create_dedicated_session)
        .with(name: 'legion-logging').and_return(mock_session)
      allow(mock_channel).to receive(:topic).with('legion.logging', durable: true).and_return(mock_exchange)
    end

    it 'wires log_writer to a callable lambda' do
      service.send(:setup_logging_transport)
      expect(Legion::Logging.log_writer).to respond_to(:call)
      expect(Legion::Transport::Connection).to have_received(:create_dedicated_session).with(name: 'legion-logging')
    end

    it 'wires exception_writer to a callable lambda' do
      service.send(:setup_logging_transport)
      expect(Legion::Logging.exception_writer).to respond_to(:call)
    end

    it 'stores the dedicated session in @log_session' do
      service.send(:setup_logging_transport)
      expect(service.instance_variable_get(:@log_session)).to eq(mock_session)
    end

    it 'calls prefetch(1) on the log channel' do
      expect(mock_channel).to receive(:prefetch).with(1)
      service.send(:setup_logging_transport)
    end

    it 'publishes via exchange when log_writer is called' do
      allow(mock_exchange).to receive(:publish)
      service.send(:setup_logging_transport)
      Legion::Logging.log_writer.call({ message: 'test' }, routing_key: 'legion.logging.log.warn.core.unknown')
      expect(mock_exchange).to have_received(:publish).once
    end

    it 'publishes via exchange when exception_writer is called' do
      allow(mock_exchange).to receive(:publish)
      service.send(:setup_logging_transport)
      Legion::Logging.exception_writer.call(
        { message: 'boom' },
        routing_key: 'legion.logging.exception.error.core.unknown',
        headers:     { fingerprint: 'abc' },
        properties:  { content_type: 'application/json' }
      )
      expect(mock_exchange).to have_received(:publish).once
    end

    it 'skips log_writer publish when channel is closed' do
      allow(mock_channel).to receive(:open?).and_return(false)
      allow(mock_exchange).to receive(:publish)
      service.send(:setup_logging_transport)
      Legion::Logging.log_writer.call({ message: 'test' }, routing_key: 'x')
      expect(mock_exchange).not_to have_received(:publish)
    end

    it 'does not raise when log_writer publish fails' do
      allow(mock_exchange).to receive(:publish).and_raise(StandardError.new('disconnected'))
      service.send(:setup_logging_transport)
      expect do
        Legion::Logging.log_writer.call({ message: 'test' }, routing_key: 'x')
      end.not_to raise_error
    end
  end
end

RSpec.describe 'Service#teardown_logging_transport' do
  let(:service) { Legion::Service.allocate }

  after do
    Legion::Logging.log_writer = nil
    Legion::Logging.exception_writer = nil
  end

  it 'resets log_writer to no-op' do
    Legion::Logging.log_writer = ->(_e, _routing_key:) { 'test' }
    service.send(:teardown_logging_transport)
    expect { Legion::Logging.log_writer.call({}, routing_key: 'x') }.not_to raise_error
  end

  it 'resets exception_writer to no-op' do
    Legion::Logging.exception_writer = ->(_e, _routing_key:, _headers:, _properties:) { 'test' }
    service.send(:teardown_logging_transport)
    expect do
      Legion::Logging.exception_writer.call({}, routing_key: 'x', headers: {}, properties: {})
    end.not_to raise_error
  end

  it 'closes and clears @log_session when open' do
    mock_session = double('session', respond_to?: true, open?: true, close: nil)
    service.instance_variable_set(:@log_session, mock_session)
    service.send(:teardown_logging_transport)
    expect(mock_session).to have_received(:close)
    expect(service.instance_variable_get(:@log_session)).to be_nil
  end

  it 'skips close when session is already closed' do
    mock_session = double('session', respond_to?: true, open?: false)
    allow(mock_session).to receive(:close)
    service.instance_variable_set(:@log_session, mock_session)
    service.send(:teardown_logging_transport)
    expect(mock_session).not_to have_received(:close)
  end

  it 'does not raise when @log_session is nil' do
    expect { service.send(:teardown_logging_transport) }.not_to raise_error
  end
end
