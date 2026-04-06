# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Tools::EmbeddingCache do
  before { described_class.clear }

  let(:vector) { [0.1, 0.2, 0.3, 0.4] }

  describe '.lookup' do
    it 'returns nil for unknown hash' do
      expect(described_class.lookup(content_hash: 'abc', model: 'test')).to be_nil
    end

    it 'returns cached vector after store (L0 hit)' do
      described_class.store(content_hash: 'abc', model: 'test', tool_name: 'x', vector: vector)
      expect(described_class.lookup(content_hash: 'abc', model: 'test')).to eq(vector)
    end

    it 'returns nil when model differs' do
      described_class.store(content_hash: 'abc', model: 'test', tool_name: 'x', vector: vector)
      expect(described_class.lookup(content_hash: 'abc', model: 'other')).to be_nil
    end
  end

  describe '.bulk_lookup' do
    it 'returns hash of hits' do
      described_class.store(content_hash: 'a', model: 'm', tool_name: 'x', vector: [1.0])
      described_class.store(content_hash: 'b', model: 'm', tool_name: 'y', vector: [2.0])
      result = described_class.bulk_lookup(content_hashes: %w[a b c], model: 'm')
      expect(result.keys).to contain_exactly('a', 'b')
    end
  end

  describe '.content_hash' do
    it 'is deterministic' do
      expect(described_class.content_hash('hello')).to eq(described_class.content_hash('hello'))
    end
  end

  describe '.clear' do
    it 'empties L0' do
      described_class.store(content_hash: 'a', model: 'm', tool_name: 'x', vector: [1.0])
      described_class.clear
      expect(described_class.lookup(content_hash: 'a', model: 'm')).to be_nil
    end
  end

  describe '.stats' do
    it 'returns memory count' do
      described_class.store(content_hash: 'a', model: 'm', tool_name: 'x', vector: [1.0])
      expect(described_class.stats[:memory]).to eq(1)
    end
  end
end
