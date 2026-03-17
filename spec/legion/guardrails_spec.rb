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

RSpec.describe Legion::Guardrails::RAGRelevancy do
  describe '.check' do
    it 'returns relevant when no LLM' do
      result = described_class.check(question: 'q', context: 'c', answer: 'a')
      expect(result[:relevant]).to be true
    end
  end
end
