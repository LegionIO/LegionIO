# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/provider_health'

RSpec.describe Legion::CLI::Chat::Tools::ProviderHealth do
  subject(:tool) { described_class }

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

      it 'returns health report from inventory' do
        result = tool.call
        expect(result).to include('Provider Health Report')
        expect(result).to include('anthropic')
        expect(result).to include('openai')
        expect(result).to include('offerings=1')
        expect(result).to include('models=1')
      end

      it 'returns detail for a specific native provider' do
        result = tool.call(provider: 'anthropic')
        expect(result).to include('Provider: anthropic')
        expect(result).to include('Healthy:    YES')
      end

      it 'returns not found for unknown native providers' do
        result = tool.call(provider: 'bedrock')
        expect(result).to eq('Provider not found: bedrock')
      end
    end

    it 'returns error when provider inventory is not available' do
      result = tool.call
      expect(result).to eq('LLM provider inventory not available.')
    end

    it 'does not fall back to legacy gateway provider stats' do
      stats_mod = Module.new do
        def self.health_report
          [{ provider: 'gateway', circuit: 'closed', adjustment: 0, healthy: true }]
        end
      end
      stub_const('Legion::Extensions::Llm::Gateway::Runners::ProviderStats', stats_mod)

      result = tool.call
      expect(result).to eq('LLM provider inventory not available.')
    end
  end
end
