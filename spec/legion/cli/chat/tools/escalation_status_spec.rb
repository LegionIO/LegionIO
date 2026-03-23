# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/escalation_status'

RSpec.describe Legion::CLI::Chat::Tools::EscalationStatus do
  subject(:tool) { described_class.new }

  let(:tracker_mod) do
    Module.new do
      def self.summary
        {
          total_escalations: 3,
          by_reason:         { 'quality' => 2, 'timeout' => 1 },
          by_target_model:   { 'gpt-4o' => 2, 'claude-opus-4-6' => 1 },
          by_source_model:   { 'gpt-4o-mini' => 2, 'claude-haiku-4-5' => 1 },
          recent:            [
            { from_model: 'gpt-4o-mini', to_model: 'gpt-4o', reason: 'quality' }
          ]
        }
      end

      def self.escalation_rate(window_seconds: 3600)
        { count: 3, window_seconds: window_seconds }
      end
    end
  end

  before { stub_const('Legion::LLM::EscalationTracker', tracker_mod) }

  describe '#execute' do
    it 'returns summary by default' do
      result = tool.execute
      expect(result).to include('Model Escalation Summary')
      expect(result).to include('Total Escalations: 3')
      expect(result).to include('quality')
    end

    it 'shows escalated-to models' do
      result = tool.execute
      expect(result).to include('gpt-4o')
      expect(result).to include('Escalated To')
    end

    it 'shows rate when requested' do
      result = tool.execute(action: 'rate')
      expect(result).to include('Escalation Rate')
      expect(result).to include('3 escalations')
    end

    it 'returns unavailable when tracker not defined' do
      hide_const('Legion::LLM::EscalationTracker')
      result = tool.execute
      expect(result).to eq('Escalation tracker not available.')
    end
  end
end
