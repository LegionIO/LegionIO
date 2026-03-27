# frozen_string_literal: true

require 'spec_helper'
require 'legion/dispatch'
require 'legion/dispatch/local'

RSpec.describe Legion::Dispatch::Local do
  subject(:dispatcher) { described_class.new(pool_size: 2) }

  after { dispatcher.stop }

  describe '#initialize' do
    it 'creates a dispatcher with the given pool size' do
      expect(dispatcher.capacity[:pool_size]).to eq(2)
    end

    it 'defaults pool_size from settings when not provided' do
      allow(Legion::Settings).to receive(:dig).with(:dispatch, :local_pool_size).and_return(4)
      d = described_class.new
      expect(d.capacity[:pool_size]).to eq(4)
      d.stop
    end

    it 'falls back to 8 when settings are nil' do
      allow(Legion::Settings).to receive(:dig).with(:dispatch, :local_pool_size).and_return(nil)
      d = described_class.new
      expect(d.capacity[:pool_size]).to eq(8)
      d.stop
    end
  end

  describe '#submit' do
    it 'executes the block on the thread pool' do
      result = Concurrent::IVar.new
      dispatcher.submit { result.set(:done) }
      expect(result.value(5)).to eq(:done)
    end

    it 'logs errors without crashing the pool' do
      dispatcher.submit { raise 'test explosion' }
      result = Concurrent::IVar.new
      dispatcher.submit { result.set(:still_alive) }
      expect(result.value(5)).to eq(:still_alive)
    end
  end

  describe '#stop' do
    it 'shuts down the thread pool' do
      dispatcher.stop
      expect(dispatcher.capacity[:running]).to be false
    end

    it 'is idempotent' do
      dispatcher.stop
      expect { dispatcher.stop }.not_to raise_error
    end
  end

  describe '#capacity' do
    it 'returns pool_size and queue_length' do
      cap = dispatcher.capacity
      expect(cap).to have_key(:pool_size)
      expect(cap).to have_key(:queue_length)
      expect(cap).to have_key(:running)
    end
  end
end
