# frozen_string_literal: true

require 'spec_helper'
require 'legion/compliance'

RSpec.describe Legion::Compliance::PhiTag do
  before do
    Legion::Settings.merge_settings(:compliance, Legion::Compliance::DEFAULTS)
  end

  describe '.phi?' do
    it 'returns true when metadata has phi: true' do
      expect(described_class.phi?(phi: true)).to be true
    end

    it 'returns false when phi key is absent' do
      expect(described_class.phi?({})).to be false
    end

    it 'returns false when phi is false' do
      expect(described_class.phi?(phi: false)).to be false
    end

    it 'returns false for nil metadata' do
      expect(described_class.phi?(nil)).to be false
    end
  end

  describe '.tag' do
    it 'merges phi: true and data_classification: restricted' do
      result = described_class.tag(task_id: 'abc')
      expect(result[:phi]).to be true
      expect(result[:data_classification]).to eq('restricted')
      expect(result[:task_id]).to eq('abc')
    end

    it 'preserves existing keys' do
      result = described_class.tag(foo: 'bar', baz: 42)
      expect(result[:foo]).to eq('bar')
      expect(result[:baz]).to eq(42)
    end
  end

  describe '.tagged_cache_key' do
    it 'prefixes key with phi:' do
      expect(described_class.tagged_cache_key('task:123')).to eq('phi:task:123')
    end

    it 'does not double-prefix already-tagged keys' do
      expect(described_class.tagged_cache_key('phi:task:123')).to eq('phi:task:123')
    end
  end

  describe 'feature flag' do
    it 'returns false from phi? when phi_enabled is false' do
      allow(Legion::Compliance).to receive(:phi_enabled?).and_return(false)
      expect(described_class.phi?(phi: true)).to be false
    end
  end
end
