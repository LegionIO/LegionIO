# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'

RSpec.describe Legion::Registry do
  before { described_class.clear! }

  let(:entry) do
    Legion::Registry::Entry.new(
      name: 'lex-test', version: '0.1.0', author: 'test',
      risk_tier: 'low', airb_status: 'approved', description: 'test extension'
    )
  end

  describe '.register / .lookup' do
    it 'stores and retrieves entries' do
      described_class.register(entry)
      expect(described_class.lookup('lex-test')).to eq(entry)
    end
  end

  describe '.unregister' do
    it 'removes entries' do
      described_class.register(entry)
      described_class.unregister('lex-test')
      expect(described_class.lookup('lex-test')).to be_nil
    end
  end

  describe '.all' do
    it 'returns all entries' do
      described_class.register(entry)
      expect(described_class.all).to eq([entry])
    end
  end

  describe '.search' do
    it 'finds by name' do
      described_class.register(entry)
      expect(described_class.search('test').size).to eq(1)
    end

    it 'finds by description' do
      described_class.register(entry)
      expect(described_class.search('extension').size).to eq(1)
    end

    it 'returns empty for no match' do
      described_class.register(entry)
      expect(described_class.search('nonexistent')).to be_empty
    end
  end

  describe '.approved' do
    it 'filters by approved status' do
      described_class.register(entry)
      pending_entry = Legion::Registry::Entry.new(name: 'lex-pending', airb_status: 'pending')
      described_class.register(pending_entry)
      expect(described_class.approved.map(&:name)).to eq(['lex-test'])
    end
  end

  describe '.by_risk_tier' do
    it 'filters by tier' do
      described_class.register(entry)
      expect(described_class.by_risk_tier('low').size).to eq(1)
      expect(described_class.by_risk_tier('high').size).to eq(0)
    end
  end
end

RSpec.describe Legion::Registry::Entry do
  let(:entry) { described_class.new(name: 'lex-test', airb_status: 'approved') }

  it 'reports approved status' do
    expect(entry.approved?).to be true
  end

  it 'defaults risk_tier to low' do
    expect(entry.risk_tier).to eq('low')
  end

  it 'defaults airb_status to pending' do
    plain = described_class.new(name: 'lex-plain')
    expect(plain.airb_status).to eq('pending')
  end

  it 'serializes to hash' do
    expect(entry.to_h[:name]).to eq('lex-test')
  end
end
