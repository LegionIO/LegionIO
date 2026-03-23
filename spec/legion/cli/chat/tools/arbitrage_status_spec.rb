# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/arbitrage_status'

RSpec.describe Legion::CLI::Chat::Tools::ArbitrageStatus do
  subject(:tool) { described_class.new }

  let(:arb_mod) do
    Module.new do
      def self.enabled?
        true
      end

      def self.cost_table
        {
          'gpt-4o'      => { input: 2.5, output: 10.0 },
          'gpt-4o-mini' => { input: 0.15, output: 0.60 }
        }
      end

      def self.cheapest_for(capability:, **)
        capability == :reasoning ? 'gpt-4o' : 'gpt-4o-mini'
      end

      def self.estimated_cost(model:, **)
        model == 'gpt-4o' ? 0.0075 : 0.000225
      end
    end
  end

  before do
    stub_const('Legion::LLM::Arbitrage', arb_mod)
  end

  describe '#execute' do
    it 'returns overview with cost table' do
      result = tool.execute
      expect(result).to include('LLM Cost Arbitrage')
      expect(result).to include('gpt-4o')
      expect(result).to include('gpt-4o-mini')
      expect(result).to include('Enabled: YES')
    end

    it 'shows cheapest per tier when enabled' do
      result = tool.execute
      expect(result).to include('Cheapest per tier')
      expect(result).to include('basic')
      expect(result).to include('reasoning')
    end

    it 'returns specific tier info' do
      result = tool.execute(capability: 'reasoning')
      expect(result).to include('tier: reasoning')
      expect(result).to include('gpt-4o')
    end

    it 'returns error for invalid tier' do
      result = tool.execute(capability: 'invalid')
      expect(result).to include('Invalid tier')
    end

    it 'returns unavailable when module not defined' do
      hide_const('Legion::LLM::Arbitrage')
      result = tool.execute
      expect(result).to eq('LLM arbitrage module not available.')
    end
  end
end
