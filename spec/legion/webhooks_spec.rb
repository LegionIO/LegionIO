# frozen_string_literal: true

require 'spec_helper'
require 'legion/webhooks'

RSpec.describe Legion::Webhooks do
  describe '.compute_signature' do
    it 'returns HMAC-SHA256 hex digest' do
      sig = described_class.compute_signature('secret', '{"event":"test"}')
      expect(sig).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'is deterministic' do
      s1 = described_class.compute_signature('key', 'body')
      s2 = described_class.compute_signature('key', 'body')
      expect(s1).to eq(s2)
    end

    it 'differs with different secrets' do
      s1 = described_class.compute_signature('key1', 'body')
      s2 = described_class.compute_signature('key2', 'body')
      expect(s1).not_to eq(s2)
    end
  end

  describe '.list' do
    it 'returns empty array when data unavailable' do
      expect(described_class.list).to eq([])
    end
  end

  describe '.register' do
    it 'returns error when data unavailable' do
      result = described_class.register(url: 'https://example.com/hook', secret: 'abc')
      expect(result[:error]).to eq('data_unavailable')
    end
  end

  describe '.dispatch' do
    it 'returns nil when data unavailable' do
      expect(described_class.dispatch('test.event', {})).to be_nil
    end
  end
end
