# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/model_comparison'

RSpec.describe Legion::CLI::Chat::Tools::ModelComparison do
  subject(:tool) { described_class.new }

  describe '#execute' do
    it 'returns comparison table for all models' do
      result = tool.execute
      expect(result).to include('Model Comparison')
      expect(result).to include('gpt-4o-mini')
      expect(result).to include('claude-sonnet-4-6')
    end

    it 'filters by model name substring' do
      result = tool.execute(models: 'claude')
      expect(result).to include('claude-sonnet-4-6')
      expect(result).not_to include('gpt-4o-mini')
    end

    it 'returns no matching message for unknown model' do
      result = tool.execute(models: 'nonexistent-model-xyz')
      expect(result).to eq('No matching models found.')
    end

    it 'includes cost estimate' do
      result = tool.execute(tokens: 5000)
      expect(result).to include('5000 input')
      expect(result).to include('Est. Cost')
    end

    it 'shows price ratio when multiple models compared' do
      result = tool.execute
      expect(result).to include('more expensive than')
    end

    it 'uses CostTracker pricing when available' do
      tracker = Module.new
      tracker.const_set(:DEFAULT_PRICING, { 'test-model' => { input: 1.0, output: 2.0 } }.freeze)
      stub_const('Legion::LLM::CostTracker', tracker)

      result = tool.execute
      expect(result).to include('test-model')
    end
  end
end
