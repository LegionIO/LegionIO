# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/shadow_eval_status'

RSpec.describe Legion::CLI::Chat::Tools::ShadowEvalStatus do
  subject(:tool) { described_class.new }

  let(:shadow_mod) do
    Module.new do
      def self.summary
        {
          total_evaluations:  3,
          avg_length_ratio:   1.2,
          avg_cost_savings:   0.65,
          total_primary_cost: 0.001234,
          total_shadow_cost:  0.000432,
          models_evaluated:   %w[gpt-4o-mini claude-haiku-4-5]
        }
      end

      def self.history
        [
          { primary_model: 'gpt-4o', shadow_model: 'gpt-4o-mini',
            length_ratio: 1.1, cost_savings: 0.7, evaluated_at: Time.now.utc }
        ]
      end
    end
  end

  before do
    stub_const('Legion::LLM::ShadowEval', shadow_mod)
  end

  describe '#execute' do
    it 'returns summary by default' do
      result = tool.execute
      expect(result).to include('Shadow Evaluation Summary')
      expect(result).to include('Evaluations:      3')
      expect(result).to include('65.0%')
    end

    it 'returns history when requested' do
      result = tool.execute(action: 'history')
      expect(result).to include('Shadow Evaluation History')
      expect(result).to include('gpt-4o')
      expect(result).to include('gpt-4o-mini')
    end

    it 'returns unavailable when module not defined' do
      hide_const('Legion::LLM::ShadowEval')
      result = tool.execute
      expect(result).to eq('Shadow evaluation not available.')
    end

    it 'shows enable hint when no evaluations' do
      empty_mod = Module.new do
        def self.summary
          {
            total_evaluations: 0, avg_length_ratio: 0.0, avg_cost_savings: 0.0,
            total_primary_cost: 0.0, total_shadow_cost: 0.0, models_evaluated: []
          }
        end
      end
      stub_const('Legion::LLM::ShadowEval', empty_mod)
      result = tool.execute
      expect(result).to include('llm.shadow.enabled')
    end
  end
end
