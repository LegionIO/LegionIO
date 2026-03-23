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
    stub_const('Legion::Extensions::LLM::Gateway::Runners::ProviderStats', stats_mod)
  end

  describe '#execute' do
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

    it 'returns error when gateway not available' do
      hide_const('Legion::Extensions::LLM::Gateway::Runners::ProviderStats')
      result = tool.execute
      expect(result).to eq('LLM gateway not available.')
    end

    it 'includes circuit summary in report' do
      result = tool.execute
      expect(result).to include('1 closed')
      expect(result).to include('1 open')
    end
  end
end
