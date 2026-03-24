# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'legion/data/retention'
require 'legion/audit/archiver'

RSpec.describe Legion::Audit::Archiver do
  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Settings).to receive(:[]).with(:audit) do
      { retention: { enabled: true, hot_days: 90, warm_days: 365,
                     cold_years: 7, cold_storage: '/tmp/audit-test/',
                     cold_backend: 'local', verify_on_archive: true } }
    end
  end

  describe '.enabled?' do
    it 'returns true when setting is true' do
      expect(described_class.enabled?).to be true
    end

    it 'returns false when setting is absent' do
      allow(Legion::Settings).to receive(:[]).with(:audit).and_return({ retention: {} })
      expect(described_class.enabled?).to be false
    end
  end

  describe '.archive_to_warm' do
    it 'delegates to Retention.archive_old_records and returns result hash' do
      allow(Legion::Data::Retention).to receive(:archive_old_records)
        .with(table: :audit_log, archive_after_days: 90)
        .and_return({ archived: 3, table: :audit_log })

      result = described_class.archive_to_warm
      expect(result).to eq({ moved: 3, from: :hot, to: :warm })
    end

    it 'returns no-op result when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.archive_to_warm).to eq({ moved: 0, skipped: true })
    end
  end

  describe '.archive_to_cold' do
    let(:warm_record) do
      { id: 1, event_type: 'runner_execution', principal_id: 'agent:test',
        action: 'run', resource: 'lex-test.runner.fn', source: 'amqp',
        status: 'success', detail: nil, record_hash: 'abc123', previous_hash: '0' * 64,
        retention_tier: 'warm', created_at: Time.now - (400 * 86_400) }
    end

    before do
      ordered_ds = double('ordered_ds', all: [warm_record])
      filtered_ds = double('filtered_ds', count: 1, order: ordered_ds, delete: nil)
      dataset = double('dataset', where: filtered_ds)
      db = double('db', table_exists?: true)
      allow(db).to receive(:[]).and_return(dataset)
      allow(Legion::Data).to receive(:connection).and_return(db)
      allow(Legion::Audit::ColdStorage).to receive(:upload).and_return({ path: '/tmp/audit-test/test.jsonl.gz' })
      allow(described_class).to receive(:write_manifest).and_return(true)
    end

    it 'returns a result hash with moved count' do
      result = described_class.archive_to_cold
      expect(result).to have_key(:moved)
    end

    it 'is a no-op when disabled' do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.archive_to_cold).to eq({ moved: 0, skipped: true })
    end
  end

  describe '.verify_chain' do
    let(:records) do
      [
        { id: 1, record_hash: 'aaa', previous_hash: '0' * 64 },
        { id: 2, record_hash: 'bbb', previous_hash: 'aaa' }
      ]
    end

    it 'delegates to HashChain.verify_chain' do
      allow(described_class).to receive(:load_records_for_tier).and_return(records)
      allow(Legion::Audit::HashChain).to receive(:verify_chain).with(records)
        .and_return({ valid: true, broken_links: [], records_checked: 2 })

      result = described_class.verify_chain(tier: :warm)
      expect(result[:valid]).to be true
      expect(result[:records_checked]).to eq 2
    end
  end
end
