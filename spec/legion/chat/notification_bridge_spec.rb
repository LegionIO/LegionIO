# frozen_string_literal: true

require 'spec_helper'
require 'legion/chat/notification_queue'
require 'legion/chat/notification_bridge'

RSpec.describe Legion::Chat::NotificationBridge do
  let(:queue) { Legion::Chat::NotificationQueue.new }
  let(:bridge) { described_class.new(queue: queue) }

  describe '#match_priority (via send)' do
    it 'matches alert patterns as critical' do
      priority = bridge.send(:match_priority, 'alert.fired')
      expect(priority).to eq(:critical)
    end

    it 'matches extinction wildcard as critical' do
      priority = bridge.send(:match_priority, 'extinction.mesh_isolation')
      expect(priority).to eq(:critical)
    end

    it 'matches runner.failure as info' do
      priority = bridge.send(:match_priority, 'runner.failure')
      expect(priority).to eq(:info)
    end

    it 'returns nil for unmatched events' do
      priority = bridge.send(:match_priority, 'some.random.event')
      expect(priority).to be_nil
    end
  end

  describe '#format_notification' do
    it 'formats alert events' do
      msg = bridge.send(:format_notification, 'alert.fired', { rule: 'error_spike', severity: 'warning' })
      expect(msg).to include('[ALERT]')
      expect(msg).to include('error_spike')
    end

    it 'formats extinction events' do
      msg = bridge.send(:format_notification, 'extinction.mesh_isolation', {})
      expect(msg).to include('[EXTINCTION]')
    end

    it 'formats runner failure events' do
      msg = bridge.send(:format_notification, 'runner.failure', { extension: 'lex-http', function: 'get' })
      expect(msg).to include('[FAIL]')
    end

    it 'formats unknown events with event name' do
      msg = bridge.send(:format_notification, 'custom.event', {})
      expect(msg).to include('[custom.event]')
    end
  end

  describe '#pending_notifications' do
    it 'returns empty when no notifications' do
      expect(bridge.pending_notifications).to eq([])
    end
  end

  describe '#has_urgent?' do
    it 'delegates to queue' do
      expect(bridge.has_urgent?).to be false
    end
  end
end
