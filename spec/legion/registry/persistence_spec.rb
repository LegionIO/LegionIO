# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'
require 'legion/registry/persistence'

RSpec.describe Legion::Registry::Persistence do
  before { Legion::Registry.clear! }

  describe '.data_available?' do
    it 'returns a boolean' do
      expect(described_class.data_available?).to be(true).or be(false)
    end
  end

  describe '.load_from_db' do
    context 'when data is not available' do
      before { allow(described_class).to receive(:data_available?).and_return(false) }

      it 'returns 0' do
        expect(described_class.load_from_db).to eq(0)
      end
    end

    context 'when data is available' do
      let(:mock_dataset) do
        [
          {
            name:        'lex-http',
            version:     '0.2.0',
            author:      'test',
            description: 'HTTP client extension',
            status:      'active',
            airb_status: 'approved',
            risk_tier:   'medium'
          },
          {
            name:        'lex-redis',
            version:     '0.1.0',
            author:      'test',
            description: 'Redis extension',
            status:      'active',
            airb_status: 'pending',
            risk_tier:   'low'
          }
        ]
      end

      before do
        allow(described_class).to receive(:data_available?).and_return(true)
        allow(described_class).to receive(:registry_dataset).and_return(mock_dataset)
        # Prevent persist from firing during load_from_db (register hook)
        allow(Legion::Registry::Persistence).to receive(:persist).and_return(true)
      end

      it 'populates the registry from DB rows' do
        count = described_class.load_from_db
        expect(count).to eq(2)
      end

      it 'registers each entry in Legion::Registry' do
        described_class.load_from_db
        expect(Legion::Registry.lookup('lex-http')).not_to be_nil
        expect(Legion::Registry.lookup('lex-redis')).not_to be_nil
      end

      it 'maps status as symbol' do
        described_class.load_from_db
        entry = Legion::Registry.lookup('lex-http')
        expect(entry.status).to eq(:active)
      end
    end
  end

  describe '.persist' do
    let(:entry) do
      Legion::Registry::Entry.new(
        name:        'lex-test',
        version:     '1.0.0',
        description: 'Test extension',
        status:      :active,
        airb_status: 'approved',
        risk_tier:   'low'
      )
    end

    context 'when data is not available' do
      before { allow(described_class).to receive(:data_available?).and_return(false) }

      it 'returns false' do
        expect(described_class.persist(entry)).to be false
      end
    end

    context 'when data is available and row does not exist' do
      let(:mock_dataset) { double('dataset') }

      before do
        allow(described_class).to receive(:data_available?).and_return(true)
        allow(described_class).to receive(:registry_dataset).and_return(mock_dataset)
        allow(mock_dataset).to receive(:where).with(name: 'lex-test').and_return(mock_dataset)
        allow(mock_dataset).to receive(:first).and_return(nil)
        allow(mock_dataset).to receive(:insert).and_return(1)
      end

      it 'inserts and returns true' do
        expect(mock_dataset).to receive(:insert).with(
          hash_including(name: 'lex-test', status: 'active', created_at: anything, updated_at: anything)
        )
        expect(described_class.persist(entry)).to be true
      end
    end

    context 'when data is available and row exists' do
      let(:mock_dataset) { double('dataset') }
      let(:existing_row) { { name: 'lex-test', status: 'active' } }

      before do
        allow(described_class).to receive(:data_available?).and_return(true)
        allow(described_class).to receive(:registry_dataset).and_return(mock_dataset)
        allow(mock_dataset).to receive(:where).with(name: 'lex-test').and_return(mock_dataset)
        allow(mock_dataset).to receive(:first).and_return(existing_row)
        allow(mock_dataset).to receive(:update).and_return(1)
      end

      it 'updates and returns true' do
        expect(mock_dataset).to receive(:update).with(
          hash_including(name: 'lex-test', status: 'active', updated_at: anything)
        )
        expect(described_class.persist(entry)).to be true
      end
    end

    context 'when a DB error occurs' do
      let(:mock_dataset) { double('dataset') }

      before do
        allow(described_class).to receive(:data_available?).and_return(true)
        allow(described_class).to receive(:registry_dataset).and_return(mock_dataset)
        allow(mock_dataset).to receive(:where).and_raise(StandardError, 'db error')
      end

      it 'returns false' do
        expect(described_class.persist(entry)).to be false
      end
    end
  end

  describe 'module_name derivation via .persistence_attrs (via persist)' do
    let(:mock_dataset) { double('dataset') }

    before do
      allow(described_class).to receive(:data_available?).and_return(true)
      allow(described_class).to receive(:registry_dataset).and_return(mock_dataset)
      allow(mock_dataset).to receive(:where).with(name: 'lex-azure-ai').and_return(mock_dataset)
      allow(mock_dataset).to receive(:first).and_return(nil)
    end

    it 'derives module_name by capitalizing each segment' do
      entry = Legion::Registry::Entry.new(name: 'lex-azure-ai', description: 'test')
      expect(mock_dataset).to receive(:insert).with(
        hash_including(module_name: 'Lex::Azure::Ai')
      )
      described_class.persist(entry)
    end
  end
end
