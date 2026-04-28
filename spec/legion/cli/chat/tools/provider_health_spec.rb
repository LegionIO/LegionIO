# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/provider_health'

RSpec.describe Legion::CLI::Chat::Tools::ProviderHealth do
  subject(:tool) { described_class.new }

  let(:stats_mod) do
    Module.new do
      def self.health_report
        [
          { provider: 'anthropic', circuit: 'closed', adjustment: 0, healthy: true },
          { provider: 'openai', circuit: 'open', adjustment: -50, healthy: false }
        ]
      end

      def self.provider_detail(provider:)
        { provider: provider.to_s, circuit: 'closed', adjustment: 0, healthy: true }
      end

      def self.circuit_summary
        { total: 2, closed: 1, open: 1, half_open: 0 }
      end
    end
  end

  before do
    stub_const('Legion::Extensions::Llm::Gateway::Runners::ProviderStats', stats_mod)
  end

  describe '#execute' do
    context 'when native provider inventory is loaded' do
      let(:inventory_mod) do
        Module.new do
          def self.providers
            {
              anthropic: [
                {
                  model:             'claude-sonnet-4-6',
                  type:              :inference,
                  provider_instance: 'bedrock-east-2',
                  health:            { circuit_state: 'closed', adjustment: 0 }
                }
              ],
              openai:    [
                {
                  model:       'gpt-4.1',
                  type:        :chat,
                  instance_id: 'frontier-openai',
                  health:      { circuit_state: 'open', adjustment: -50 }
                }
              ]
            }
          end
        end
      end

      before do
        stub_const('Legion::LLM::Inventory', inventory_mod)
      end

      it 'returns health report from inventory before gateway stats' do
        result = tool.execute
        expect(result).to include('Provider Health Report')
        expect(result).to include('anthropic')
        expect(result).to include('openai')
        expect(result).to include('offerings=1')
        expect(result).to include('models=1')
      end

      it 'returns detail for a specific native provider' do
        result = tool.execute(provider: 'anthropic')
        expect(result).to include('Provider: anthropic')
        expect(result).to include('Healthy:    YES')
      end

      it 'returns not found for unknown native providers' do
        result = tool.execute(provider: 'bedrock')
        expect(result).to eq('Provider not found: bedrock')
      end
    end

    it 'returns health report by default' do
      result = tool.execute
      expect(result).to include('Provider Health Report')
      expect(result).to include('anthropic')
      expect(result).to include('openai')
    end

    it 'returns detail for a specific provider' do
      result = tool.execute(provider: 'anthropic')
      expect(result).to include('Provider: anthropic')
      expect(result).to include('Healthy:    YES')
    end

    it 'returns error when provider inventory is not available' do
      hide_const('Legion::Extensions::Llm::Gateway::Runners::ProviderStats')
      result = tool.execute
      expect(result).to eq('LLM provider inventory not available.')
    end

    it 'includes circuit summary in report' do
      result = tool.execute
      expect(result).to include('1 closed')
      expect(result).to include('1 open')
    end
  end
end
