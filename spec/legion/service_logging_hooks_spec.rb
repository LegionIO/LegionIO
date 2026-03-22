# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Service logging hooks registration' do
  let(:service) { Legion::Service.allocate }
  let(:mock_exchange) { double('exchange') }

  before do
    stub_const('Legion::Transport::Exchanges::Logging', Class.new)
    allow(Legion::Transport::Exchanges::Logging).to receive(:new).and_return(mock_exchange)
    allow(mock_exchange).to receive(:publish)
    allow(Legion::Transport::Connection).to receive(:session_open?).and_return(true)
    Legion::Logging.clear_hooks!
  end

  after do
    Legion::Logging.disable_hooks!
    Legion::Logging.clear_hooks!
  end

  describe '#register_logging_hooks' do
    it 'registers hooks for fatal, error, and warn' do
      service.send(:register_logging_hooks)
      expect(Legion::Logging::Hooks.hooks[:fatal].size).to eq(1)
      expect(Legion::Logging::Hooks.hooks[:error].size).to eq(1)
      expect(Legion::Logging::Hooks.hooks[:warn].size).to eq(1)
    end

    it 'enables hooks after registration' do
      service.send(:register_logging_hooks)
      expect(Legion::Logging::Hooks.enabled?).to be true
    end

    it 'skips registration when transport is not connected' do
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(false)
      service.send(:register_logging_hooks)
      expect(Legion::Logging::Hooks.hooks[:fatal]).to be_empty
      expect(Legion::Logging::Hooks.enabled?).to be false
    end

    it 'publishes to exchange when a fatal is logged' do
      service.send(:register_logging_hooks)
      Legion::Logging.fatal('test fatal')
      expect(mock_exchange).to have_received(:publish).once
    end

    it 'uses correct routing key pattern' do
      service.send(:register_logging_hooks)
      Legion::Logging.fatal('test fatal')
      expect(mock_exchange).to have_received(:publish).with(
        anything,
        hash_including(routing_key: 'legion.core.fatal')
      )
    end

    it 'skips publish when connection drops mid-operation' do
      service.send(:register_logging_hooks)
      allow(Legion::Transport::Connection).to receive(:session_open?).and_return(false)
      Legion::Logging.fatal('test fatal')
      expect(mock_exchange).not_to have_received(:publish)
    end

    it 'does not raise when exchange publish fails' do
      service.send(:register_logging_hooks)
      allow(mock_exchange).to receive(:publish).and_raise(StandardError.new('connection lost'))
      expect { Legion::Logging.fatal('test fatal') }.not_to raise_error
    end
  end
end
