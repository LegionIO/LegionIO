# frozen_string_literal: true

require 'spec_helper'
require 'legion/events'

# rubocop:disable Metrics/BlockLength
RSpec.describe Legion::Events do
  before { described_class.clear }
  after { described_class.clear }

  describe '.on' do
    it 'registers a listener and returns the block' do
      block = described_class.on('test.event') { |_e| nil }
      expect(block).to be_a(Proc)
    end

    it 'registers multiple listeners for same event' do
      described_class.on('test.event') { |_e| nil }
      described_class.on('test.event') { |_e| nil }
      expect(described_class.listener_count('test.event')).to eq(2)
    end
  end

  describe '.emit' do
    it 'calls registered listeners with event hash' do
      received = nil
      described_class.on('test.event') { |e| received = e }
      described_class.emit('test.event', key: 'value')
      expect(received).to be_a(Hash)
      expect(received[:key]).to eq('value')
    end

    it 'includes event name and timestamp in event hash' do
      received = nil
      described_class.on('test.event') { |e| received = e }
      described_class.emit('test.event')
      expect(received[:event]).to eq('test.event')
      expect(received[:timestamp]).to be_a(Time)
    end

    it 'fires wildcard listeners' do
      received = nil
      described_class.on('*') { |e| received = e }
      described_class.emit('any.event', data: 42)
      expect(received[:event]).to eq('any.event')
      expect(received[:data]).to eq(42)
    end

    it 'catches listener errors without propagating' do
      described_class.on('error.event') { |_e| raise 'boom' }
      expect { described_class.emit('error.event') }.not_to raise_error
    end

    it 'returns the event hash' do
      result = described_class.emit('test.event', key: 'val')
      expect(result).to be_a(Hash)
      expect(result[:event]).to eq('test.event')
    end
  end

  describe '.off' do
    it 'removes all listeners for an event' do
      described_class.on('test.event') { |_e| nil }
      described_class.on('test.event') { |_e| nil }
      described_class.off('test.event')
      expect(described_class.listener_count('test.event')).to eq(0)
    end

    it 'removes a specific listener' do
      block = described_class.on('test.event') { |_e| nil }
      described_class.on('test.event') { |_e| nil }
      described_class.off('test.event', block)
      expect(described_class.listener_count('test.event')).to eq(1)
    end
  end

  describe '.once' do
    it 'fires listener only once' do
      count = 0
      described_class.once('once.event') { |_e| count += 1 }
      described_class.emit('once.event')
      described_class.emit('once.event')
      expect(count).to eq(1)
    end

    it 'auto-removes the listener after firing' do
      described_class.once('once.event') { |_e| nil }
      described_class.emit('once.event')
      expect(described_class.listener_count('once.event')).to eq(0)
    end
  end

  describe '.clear' do
    it 'removes all listeners' do
      described_class.on('a') { |_e| nil }
      described_class.on('b') { |_e| nil }
      described_class.clear
      expect(described_class.listener_count).to eq(0)
    end
  end

  describe '.listener_count' do
    it 'returns count for a specific event' do
      described_class.on('test') { |_e| nil }
      described_class.on('test') { |_e| nil }
      expect(described_class.listener_count('test')).to eq(2)
    end

    it 'returns total count across all events' do
      described_class.on('a') { |_e| nil }
      described_class.on('b') { |_e| nil }
      described_class.on('b') { |_e| nil }
      expect(described_class.listener_count).to eq(3)
    end

    it 'returns 0 for events with no listeners' do
      expect(described_class.listener_count('nonexistent')).to eq(0)
    end
  end
end
# rubocop:enable Metrics/BlockLength
