# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit/hash_chain'

RSpec.describe Legion::Audit::HashChain do
  let(:base_record) do
    { seq: 1, principal_id: 'w1', action: 'test', resource: 'task', source: 'mcp',
      status: 'success', detail: '{}', created_at: '2026-03-16T00:00:00Z',
      previous_hash: described_class::GENESIS_HASH }
  end

  describe '.compute_hash' do
    it 'returns a 64-character hex string' do
      hash = described_class.compute_hash(base_record)
      expect(hash).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'is deterministic' do
      expect(described_class.compute_hash(base_record)).to eq(described_class.compute_hash(base_record))
    end

    it 'changes when any field changes' do
      modified = base_record.merge(action: 'modified')
      expect(described_class.compute_hash(base_record)).not_to eq(described_class.compute_hash(modified))
    end

    it 'changes when previous_hash changes' do
      modified = base_record.merge(previous_hash: 'a' * 64)
      expect(described_class.compute_hash(base_record)).not_to eq(described_class.compute_hash(modified))
    end
  end

  describe '.canonical_payload' do
    it 'includes all canonical fields' do
      payload = described_class.canonical_payload(base_record)
      described_class::CANONICAL_FIELDS.each do |field|
        expect(payload).to include("#{field}:")
      end
    end
  end

  describe '.verify_chain' do
    it 'validates a correct chain' do
      r1 = { id: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      r2 = { id: 2, record_hash: 'bbb', previous_hash: 'aaa' }
      r3 = { id: 3, record_hash: 'ccc', previous_hash: 'bbb' }
      result = described_class.verify_chain([r1, r2, r3])
      expect(result[:valid]).to be true
      expect(result[:broken_links]).to be_empty
      expect(result[:records_checked]).to eq(3)
    end

    it 'detects a broken link' do
      r1 = { id: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      r2 = { id: 2, record_hash: 'bbb', previous_hash: 'TAMPERED' }
      result = described_class.verify_chain([r1, r2])
      expect(result[:valid]).to be false
      expect(result[:broken_links].size).to eq(1)
      expect(result[:broken_links].first[:id]).to eq(2)
    end

    it 'handles single record' do
      r1 = { id: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      result = described_class.verify_chain([r1])
      expect(result[:valid]).to be true
    end

    it 'handles empty array' do
      result = described_class.verify_chain([])
      expect(result[:valid]).to be true
      expect(result[:records_checked]).to eq(0)
    end

    it 'detects a gap in sequence numbers' do
      r1 = { id: 1, seq: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      r2 = { id: 2, seq: 3, record_hash: 'bbb', previous_hash: 'aaa' }
      result = described_class.verify_chain([r1, r2])
      expect(result[:valid]).to be false
      gap = result[:broken_links].find { |b| b[:type] == :gap }
      expect(gap).not_to be_nil
      expect(gap[:expected_seq]).to eq(2)
      expect(gap[:got_seq]).to eq(3)
    end

    it 'passes when sequence numbers are contiguous' do
      r1 = { id: 1, seq: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      r2 = { id: 2, seq: 2, record_hash: 'bbb', previous_hash: 'aaa' }
      r3 = { id: 3, seq: 3, record_hash: 'ccc', previous_hash: 'bbb' }
      result = described_class.verify_chain([r1, r2, r3])
      expect(result[:valid]).to be true
    end

    it 'skips gap check when seq is absent for backwards compatibility' do
      r1 = { id: 1, record_hash: 'aaa', previous_hash: described_class::GENESIS_HASH }
      r2 = { id: 2, record_hash: 'bbb', previous_hash: 'aaa' }
      result = described_class.verify_chain([r1, r2])
      expect(result[:valid]).to be true
    end
  end
end
