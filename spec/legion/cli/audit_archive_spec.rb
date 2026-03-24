# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sequel'
require 'legion/data/retention'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/audit/archiver'
require 'legion/cli/audit_command'

RSpec.describe Legion::CLI::Audit do
  before do
    allow(Legion::CLI::Connection).to receive(:ensure_settings)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
    allow(Legion::Audit::Archiver).to receive(:enabled?).and_return(true)
  end

  describe 'archive --dry-run' do
    it 'outputs DRY RUN preview without executing' do
      allow(Legion::Data::Retention).to receive(:retention_status)
        .with(table: :audit_log)
        .and_return({ active_count: 5000, archived_count: 1200,
                      oldest_active: Time.now - (91 * 86_400),
                      oldest_archived: Time.now - (370 * 86_400) })

      expect { described_class.start(%w[archive --dry-run]) }.to output(/DRY RUN/).to_stdout
    end
  end

  describe 'archive --execute' do
    it 'calls archive_to_warm and archive_to_cold and outputs results' do
      allow(Legion::Audit::Archiver).to receive(:archive_to_warm)
        .and_return({ moved: 10, from: :hot, to: :warm })
      allow(Legion::Audit::Archiver).to receive(:archive_to_cold)
        .and_return({ moved: 5, path: '/tmp/test.jsonl.gz', checksum: 'abc' })
      allow(Legion::Audit::Archiver).to receive(:verify_chain)
        .and_return({ valid: true, records_checked: 5, broken_links: [] })

      expect { described_class.start(%w[archive --execute]) }
        .to output(/Archived 10 records to warm/).to_stdout
    end
  end

  describe 'verify_chain' do
    it 'outputs valid chain result' do
      allow(Legion::Audit::Archiver).to receive(:verify_chain)
        .and_return({ valid: true, records_checked: 42, broken_links: [] })

      expect { described_class.start(%w[verify_chain --tier hot]) }
        .to output(/42 records verified/).to_stdout
    end

    it 'exits 1 on broken chain' do
      allow(Legion::Audit::Archiver).to receive(:verify_chain)
        .and_return({ valid: false, records_checked: 10,
                      broken_links: [{ id: 5, expected: 'aaa', got: 'bbb' }] })

      expect { described_class.start(%w[verify_chain --tier hot]) }
        .to raise_error(SystemExit)
    end
  end
end
