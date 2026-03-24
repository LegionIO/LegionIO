# frozen_string_literal: true

require 'spec_helper'
require 'legion/guardrails'

RSpec.describe Legion::Guardrails::EmbeddingSimilarity do
  describe '.cosine_distance' do
    it 'returns 0 for identical vectors' do
      v = [1.0, 0.0, 0.0]
      expect(described_class.cosine_distance(v, v)).to be_within(0.001).of(0.0)
    end

    it 'returns 1 for orthogonal vectors' do
      a = [1.0, 0.0]
      b = [0.0, 1.0]
      expect(described_class.cosine_distance(a, b)).to be_within(0.001).of(1.0)
    end

    it 'handles empty vectors' do
      expect(described_class.cosine_distance([], [])).to eq(1.0)
    end

    it 'handles nil vectors' do
      expect(described_class.cosine_distance(nil, nil)).to eq(1.0)
    end
  end

  describe '.check' do
    it 'returns safe when no LLM' do
      result = described_class.check('test', safe_embeddings: [], threshold: 0.3)
      expect(result[:safe]).to be true
    end
  end
end

RSpec.describe Legion::Guardrails do
  describe 'SYSTEM_CALLER' do
    subject(:caller_hash) { described_class::SYSTEM_CALLER }

    it 'nests identity under requested_by' do
      expect(caller_hash[:requested_by][:identity]).to eq('system:guardrails')
    end

    it 'uses :system type to trigger system pipeline profile' do
      expect(caller_hash[:requested_by][:type]).to eq(:system)
    end

    it 'uses :internal credential' do
      expect(caller_hash[:requested_by][:credential]).to eq(:internal)
    end

    it 'is frozen' do
      expect(caller_hash).to be_frozen
    end
  end
end

RSpec.describe Legion::Guardrails::RAGRelevancy do
  describe '.check' do
    it 'returns relevant when no LLM' do
      result = described_class.check(question: 'q', context: 'c', answer: 'a')
      expect(result[:relevant]).to be true
    end

    context 'when Legion::LLM is available' do
      let(:llm_result) { { content: '4' } }

      before do
        stub_const('Legion::LLM', Module.new)
        allow(Legion::LLM).to receive(:chat).and_return(llm_result)
      end

      it 'passes the system caller identity to avoid pipeline recursion' do
        described_class.check(question: 'q', context: 'c', answer: 'a')
        expect(Legion::LLM).to have_received(:chat).with(
          hash_including(caller: Legion::Guardrails::SYSTEM_CALLER)
        )
      end

      it 'returns relevant when score meets threshold' do
        result = described_class.check(question: 'q', context: 'c', answer: 'a', threshold: 3)
        expect(result[:relevant]).to be true
        expect(result[:score]).to eq(4)
      end

      it 'returns not relevant when score is below threshold' do
        allow(Legion::LLM).to receive(:chat).and_return({ content: '1' })
        result = described_class.check(question: 'q', context: 'c', answer: 'a', threshold: 3)
        expect(result[:relevant]).to be false
        expect(result[:score]).to eq(1)
      end

      it 'returns relevant: true on LLM error' do
        allow(Legion::LLM).to receive(:chat).and_raise(StandardError, 'boom')
        result = described_class.check(question: 'q', context: 'c', answer: 'a')
        expect(result[:relevant]).to be true
        expect(result[:reason]).to eq('check failed')
      end
    end
  end
end
