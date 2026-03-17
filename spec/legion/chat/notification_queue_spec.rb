# frozen_string_literal: true

require 'spec_helper'
require 'legion/chat/notification_queue'

RSpec.describe Legion::Chat::NotificationQueue do
  let(:queue) { described_class.new(max_size: 5) }

  describe '#push and #pop_all' do
    it 'returns notifications by priority' do
      queue.push(message: 'info msg', priority: :info)
      queue.push(message: 'critical msg', priority: :critical)
      results = queue.pop_all
      expect(results.first[:priority]).to eq(:critical)
    end

    it 'respects max_size' do
      6.times { |i| queue.push(message: "msg #{i}") }
      expect(queue.size).to eq(5)
    end

    it 'removes popped messages' do
      queue.push(message: 'test')
      queue.pop_all
      expect(queue.size).to eq(0)
    end

    it 'filters by max_priority' do
      queue.push(message: 'debug', priority: :debug)
      queue.push(message: 'critical', priority: :critical)
      results = queue.pop_all(max_priority: :critical)
      expect(results.size).to eq(1)
      expect(results.first[:priority]).to eq(:critical)
    end
  end

  describe '#has_critical?' do
    it 'returns true when critical message present' do
      queue.push(message: 'alert', priority: :critical)
      expect(queue.has_critical?).to be true
    end

    it 'returns false when no critical messages' do
      queue.push(message: 'info', priority: :info)
      expect(queue.has_critical?).to be false
    end
  end

  describe '#clear' do
    it 'empties the queue' do
      queue.push(message: 'test')
      queue.clear
      expect(queue.size).to eq(0)
    end
  end
end
