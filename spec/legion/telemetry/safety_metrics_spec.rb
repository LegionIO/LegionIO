# frozen_string_literal: true

require 'spec_helper'
require 'legion/telemetry/safety_metrics'

RSpec.describe Legion::Telemetry::SafetyMetrics do
  describe Legion::Telemetry::SlidingWindow do
    let(:window) { described_class.new(60) }

    it 'counts entries within window' do
      3.times { window.push(agent: 'a') }
      expect(window.count_for(agent: 'a')).to eq(3)
    end

    it 'filters by agent' do
      2.times { window.push(agent: 'a') }
      window.push(agent: 'b')
      expect(window.count_for(agent: 'a')).to eq(2)
      expect(window.count_for(agent: 'b')).to eq(1)
    end

    it 'expires old entries' do
      window.push(agent: 'a')
      window.instance_variable_get(:@entries) << { agent: 'a', at: Time.now - 120 }
      expect(window.count_for(agent: 'a')).to eq(1)
    end

    it 'returns ratio' do
      5.times { window.push(type: :success) }
      2.times { window.push(type: :failure) }
      total = window.count
      failures = window.count_for(type: :failure)
      expect(failures.to_f / total).to be_within(0.01).of(0.285)
    end
  end

  describe '.record_action' do
    before do
      described_class.instance_variable_set(:@windows, nil)
      described_class.init_windows
    end

    it 'increments action counter' do
      described_class.record_action(agent_id: 'worker-1')
      expect(described_class.actions_per_minute('worker-1')).to eq(1)
    end
  end

  describe '.tool_failure_ratio' do
    before do
      described_class.instance_variable_set(:@windows, nil)
      described_class.init_windows
    end

    it 'computes failure ratio' do
      8.times { described_class.record_success(agent_id: 'w1') }
      2.times { described_class.record_failure(agent_id: 'w1') }
      expect(described_class.tool_failure_ratio('w1')).to be_within(0.01).of(0.2)
    end

    it 'returns 0.0 when no events' do
      expect(described_class.tool_failure_ratio('w1')).to eq(0.0)
    end
  end

  describe '.confidence_drift' do
    before do
      described_class.instance_variable_set(:@windows, nil)
      described_class.init_windows
    end

    it 'computes average delta' do
      described_class.record_confidence(agent_id: 'w1', delta: -0.05)
      described_class.record_confidence(agent_id: 'w1', delta: -0.03)
      expect(described_class.confidence_drift('w1')).to be_within(0.001).of(-0.04)
    end
  end
end
