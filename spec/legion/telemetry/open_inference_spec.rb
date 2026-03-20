# frozen_string_literal: true

require 'spec_helper'
require 'legion/telemetry'
require 'legion/telemetry/open_inference'

RSpec.describe Legion::Telemetry::OpenInference do
  before do
    allow(Legion::Telemetry).to receive(:enabled?).and_return(false)
  end

  describe '.llm_span' do
    it 'yields when telemetry is disabled' do
      result = described_class.llm_span(model: 'claude-sonnet-4-20250514') { 42 }
      expect(result).to eq(42)
    end

    it 'passes correct attributes when telemetry is enabled' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.llm_span(model: 'gpt-4o', provider: 'openai') { :ok }
      expect(attrs['openinference.span.kind']).to eq('LLM')
      expect(attrs['llm.model_name']).to eq('gpt-4o')
      expect(attrs['llm.provider']).to eq('openai')
    end
  end

  describe '.embedding_span' do
    it 'sets EMBEDDING span kind' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.embedding_span(model: 'text-embedding-3-small') { :ok }
      expect(attrs['openinference.span.kind']).to eq('EMBEDDING')
    end
  end

  describe '.tool_span' do
    it 'sets TOOL span kind with tool name' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.tool_span(name: 'lex-github.issues.create', parameters: { repo: 'test' }) { :ok }
      expect(attrs['openinference.span.kind']).to eq('TOOL')
      expect(attrs['tool.name']).to eq('lex-github.issues.create')
    end
  end

  describe '.chain_span' do
    it 'sets CHAIN span kind' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.chain_span(type: 'task_chain') { :ok }
      expect(attrs['openinference.span.kind']).to eq('CHAIN')
    end
  end

  describe '.evaluator_span' do
    it 'sets EVALUATOR span kind' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.evaluator_span(template: 'hallucination') { { score: 0.9, passed: true } }
      expect(attrs['openinference.span.kind']).to eq('EVALUATOR')
      expect(attrs['eval.template']).to eq('hallucination')
    end
  end

  describe '.agent_span' do
    it 'sets AGENT span kind' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.agent_span(name: 'worker-1', mode: :full_active) { :ok }
      expect(attrs['openinference.span.kind']).to eq('AGENT')
      expect(attrs['agent.name']).to eq('worker-1')
    end
  end

  describe '.truncate_value' do
    it 'truncates strings longer than limit' do
      long = 'a' * 5000
      result = described_class.truncate_value(long, max: 4096)
      expect(result.length).to eq(4096)
    end

    it 'passes short strings through' do
      expect(described_class.truncate_value('hello', max: 4096)).to eq('hello')
    end
  end

  describe '.open_inference_enabled?' do
    it 'returns false when telemetry is disabled' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(false)
      expect(described_class.open_inference_enabled?).to be false
    end
  end
end
