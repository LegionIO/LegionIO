# frozen_string_literal: true

require 'spec_helper'
require 'legion/alerts'

RSpec.describe Legion::Alerts::Engine do
  let(:rules) do
    [
      { name: 'test_alert', event_pattern: 'test.*', severity: 'warning', channels: ['log'], cooldown_seconds: 0 },
      { name: 'count_alert', event_pattern: 'error.*', severity: 'critical', channels: ['log'],
        condition: { count_threshold: 3, window_seconds: 60 }, cooldown_seconds: 0 }
    ]
  end
  let(:engine) { described_class.new(rules: rules) }

  describe '#evaluate' do
    it 'fires matching rule' do
      fired = engine.evaluate('test.something', {})
      expect(fired).to include('test_alert')
    end

    it 'does not fire non-matching rule' do
      fired = engine.evaluate('unrelated.event', {})
      expect(fired).to be_empty
    end

    it 'requires count threshold before firing' do
      2.times { expect(engine.evaluate('error.fatal', {})).to be_empty }
      fired = engine.evaluate('error.fatal', {})
      expect(fired).to include('count_alert')
    end

    it 'respects cooldown' do
      rule = [{ name: 'cool', event_pattern: 'x', severity: 'info', channels: [], cooldown_seconds: 9999 }]
      e = described_class.new(rules: rule)
      e.evaluate('x', {})
      expect(e.evaluate('x', {})).to be_empty
    end

    it 'resets counter after window expires' do
      rule = [{ name: 'windowed', event_pattern: 'tick', severity: 'info', channels: [],
                condition: { count_threshold: 2, window_seconds: 1 }, cooldown_seconds: 0 }]
      e = described_class.new(rules: rule)
      e.evaluate('tick', {})

      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(e.evaluate('tick', {})).to be_empty
    end

    it 'accepts AlertRule structs directly' do
      struct = Legion::Alerts::AlertRule.new(name: 'struct_test', event_pattern: 'foo',
                                             severity: 'info', channels: [], cooldown_seconds: 0)
      e = described_class.new(rules: [struct])
      expect(e.evaluate('foo', {})).to include('struct_test')
    end
  end
end

RSpec.describe Legion::Alerts do
  describe 'DEFAULT_RULES' do
    it 'contains expected rule names' do
      names = described_class::DEFAULT_RULES.map { |r| r[:name] }
      expect(names).to include('consent_violation', 'extinction_trigger', 'error_spike', 'budget_exceeded')
    end
  end
end
