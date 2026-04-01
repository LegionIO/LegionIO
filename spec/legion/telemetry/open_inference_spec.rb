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

    it 'includes GenAI semantic convention attributes' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.llm_span(model: 'claude-sonnet-4-20250514', provider: 'anthropic') { :ok }
      expect(attrs['gen_ai.request.model']).to eq('claude-sonnet-4-20250514')
      expect(attrs['gen_ai.system']).to eq('anthropic')
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

    it 'includes GenAI attributes for embeddings' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.embedding_span(model: 'text-embedding-3-small') { :ok }
      expect(attrs['gen_ai.request.model']).to eq('text-embedding-3-small')
      expect(attrs['gen_ai.system']).to eq('embedding')
    end
  end

  describe '.annotate_llm_result' do
    let(:span) { double('span', set_attribute: nil) }

    before { allow(span).to receive(:respond_to?).with(:set_attribute).and_return(true) }

    it 'sets GenAI usage attributes' do
      result = { input_tokens: 100, output_tokens: 50, stop_reason: 'end_turn', model: 'claude-sonnet-4-20250514' }
      described_class.annotate_llm_result(span, result)

      expect(span).to have_received(:set_attribute).with('gen_ai.usage.input_tokens', 100)
      expect(span).to have_received(:set_attribute).with('gen_ai.usage.output_tokens', 50)
      expect(span).to have_received(:set_attribute).with('gen_ai.response.finish_reason', 'end_turn')
      expect(span).to have_received(:set_attribute).with('gen_ai.response.model', 'claude-sonnet-4-20250514')
    end

    it 'preserves OpenInference attributes alongside GenAI' do
      result = { input_tokens: 100, output_tokens: 50 }
      described_class.annotate_llm_result(span, result)

      expect(span).to have_received(:set_attribute).with('llm.token_count.prompt', 100)
      expect(span).to have_received(:set_attribute).with('llm.token_count.completion', 50)
      expect(span).to have_received(:set_attribute).with('gen_ai.usage.input_tokens', 100)
      expect(span).to have_received(:set_attribute).with('gen_ai.usage.output_tokens', 50)
    end
  end

  describe '.genai_attrs' do
    it 'returns model attribute' do
      result = described_class.genai_attrs(model: 'gpt-4o')
      expect(result['gen_ai.request.model']).to eq('gpt-4o')
    end

    it 'includes system when provider given' do
      result = described_class.genai_attrs(model: 'gpt-4o', provider: 'openai')
      expect(result['gen_ai.system']).to eq('openai')
    end

    it 'omits system when provider is nil' do
      result = described_class.genai_attrs(model: 'gpt-4o')
      expect(result).not_to have_key('gen_ai.system')
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

  describe '.retriever_span' do
    it 'yields when telemetry is disabled' do
      result = described_class.retriever_span(name: 'apollo-local') { 42 }
      expect(result).to eq(42)
    end

    it 'sets RETRIEVER span kind with name and optional attributes' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.retriever_span(name: 'apollo-local', query: 'what is legion?', top_k: 5) { :ok }
      expect(attrs['openinference.span.kind']).to eq('RETRIEVER')
      expect(attrs['retriever.name']).to eq('apollo-local')
      expect(attrs['retriever.top_k']).to eq(5)
    end
  end

  describe '.reranker_span' do
    it 'yields when telemetry is disabled' do
      result = described_class.reranker_span(model: 'cross-encoder') { 42 }
      expect(result).to eq(42)
    end

    it 'sets RERANKER span kind with model and optional attributes' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.reranker_span(model: 'cross-encoder', query: 'test query', top_k: 3) { :ok }
      expect(attrs['openinference.span.kind']).to eq('RERANKER')
      expect(attrs['reranker.model_name']).to eq('cross-encoder')
      expect(attrs['reranker.top_k']).to eq(3)
    end
  end

  describe '.guardrail_span' do
    it 'yields when telemetry is disabled' do
      result = described_class.guardrail_span(name: 'pii-filter') { 42 }
      expect(result).to eq(42)
    end

    it 'sets GUARDRAIL span kind with name' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      attrs = nil
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **kwargs, &block|
        attrs = kwargs[:attributes]
        block.call(nil)
      end

      described_class.guardrail_span(name: 'pii-filter', input: 'some text') { { passed: true, score: 0.95 } }
      expect(attrs['openinference.span.kind']).to eq('GUARDRAIL')
      expect(attrs['guardrail.name']).to eq('pii-filter')
    end

    it 'records score of 0 via nil check' do
      allow(Legion::Telemetry).to receive(:enabled?).and_return(true)
      recorded_score = :not_set
      fake_span = double('span')
      allow(fake_span).to receive(:respond_to?).with(:set_attribute).and_return(true)
      allow(fake_span).to receive(:set_attribute) do |key, val|
        recorded_score = val if key == 'guardrail.score'
      end
      allow(Legion::Telemetry).to receive(:with_span) do |_name, **_kwargs, &block|
        block.call(fake_span)
      end

      described_class.guardrail_span(name: 'pii-filter') { { passed: false, score: 0 } }
      expect(recorded_score).to eq(0)
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
