# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/budget_status'

RSpec.describe Legion::CLI::Chat::Tools::BudgetStatus do
  subject(:tool) { described_class.new }

  before do
    stub_const('Legion::LLM', Module.new)
    stub_const('Legion::LLM::CostTracker', Module.new do
      def self.summary
        {
          total_cost_usd: 0.025,
          total_requests: 5,
          total_input_tokens: 10_000,
          total_output_tokens: 3000,
          by_model: {
            'claude-sonnet-4-6' => { cost_usd: 0.02, requests: 3 },
            'gpt-4o-mini' => { cost_usd: 0.005, requests: 2 }
          }
        }
      end
    end)
    stub_const('Legion::LLM::Hooks::BudgetGuard', Module.new do
      def self.status
        {
          enforcing: true,
          budget_usd: 1.0,
          spent_usd: 0.025,
          remaining_usd: 0.975,
          ratio: 0.025
        }
      end
    end)
  end

  describe '#execute' do
    it 'returns budget status by default' do
      result = tool.execute
      expect(result).to include('Session Budget Status')
      expect(result).to include('Enforcing:  YES')
      expect(result).to include('Budget:')
      expect(result).to include('Requests:   5')
    end

    it 'returns cost summary when requested' do
      result = tool.execute(action: 'summary')
      expect(result).to include('Session Cost Summary')
      expect(result).to include('claude-sonnet-4-6')
      expect(result).to include('gpt-4o-mini')
    end

    it 'returns error when LLM not available' do
      hide_const('Legion::LLM')
      result = tool.execute
      expect(result).to eq('Legion::LLM not available.')
    end
  end

  describe '#execute with no budget enforced' do
    before do
      stub_const('Legion::LLM::Hooks::BudgetGuard', Module.new do
        def self.status
          { enforcing: false, budget_usd: 0.0, ratio: 0.0 }
        end
      end)
    end

    it 'shows enforcing as no' do
      result = tool.execute
      expect(result).to include('Enforcing:  no')
    end
  end

  describe '#execute summary with no requests' do
    before do
      stub_const('Legion::LLM::CostTracker', Module.new do
        def self.summary
          { total_cost_usd: 0.0, total_requests: 0, total_input_tokens: 0, total_output_tokens: 0, by_model: {} }
        end
      end)
    end

    it 'returns no requests message' do
      result = tool.execute(action: 'summary')
      expect(result).to eq('No LLM requests recorded this session.')
    end
  end
end
