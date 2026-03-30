# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'legion/data/retention'
require 'legion/audit/archiver'
require 'legion/audit/archiver_actor'

RSpec.describe Legion::Audit::ArchiverActor do
  describe '.enabled?' do
    it 'delegates to Archiver.enabled?' do
      allow(Legion::Audit::Archiver).to receive(:enabled?).and_return(false)
      expect(described_class.enabled?).to be false
    end
  end

  describe '#run_archival' do
    it 'calls archive_to_warm and archive_to_cold when enabled and time matches' do
      allow(Legion::Audit::Archiver).to receive(:enabled?).and_return(true)
      allow(Legion::Audit::Archiver).to receive(:archive_to_warm).and_return({ moved: 0 })
      allow(Legion::Audit::Archiver).to receive(:archive_to_cold).and_return({ moved: 0 })
      allow(Legion::Audit::Archiver).to receive(:verify_chain).and_return({ valid: true, records_checked: 0, broken_links: [] })
      allow(Legion::Audit::Archiver).to receive(:verify_on_archive?).and_return(true)
      allow(Legion::Logging).to receive(:info)
      allow(Legion::Logging).to receive(:error)

      # Force time to match schedule (Sunday = wday 0, hour = 2)
      target_day  = described_class.scheduled_day_of_week
      target_hour = described_class.scheduled_hour
      # Build a real Time that matches the scheduled wday and hour
      now = Time.now.utc
      days_ahead = (target_day - now.wday) % 7
      target_date = (now.to_date + days_ahead)
      fake_time = Time.utc(target_date.year, target_date.month, target_date.day, target_hour, 0, 0)
      allow(Time).to receive(:now).and_return(fake_time)

      actor = described_class.new
      expect { actor.run_archival }.not_to raise_error
      expect(Legion::Audit::Archiver).to have_received(:archive_to_warm)
    end

    it 'is a no-op when disabled' do
      allow(Legion::Audit::Archiver).to receive(:enabled?).and_return(false)
      actor = described_class.new
      expect(Legion::Audit::Archiver).not_to receive(:archive_to_warm)
      actor.run_archival
    end

    it 'is a no-op when day-of-week does not match' do
      allow(Legion::Audit::Archiver).to receive(:enabled?).and_return(true)

      wrong_day = (described_class.scheduled_day_of_week + 1) % 7
      fake_time = instance_double(Time, wday: wrong_day, hour: described_class.scheduled_hour)
      allow(fake_time).to receive(:utc).and_return(fake_time)
      allow(Time).to receive(:now).and_return(fake_time)

      actor = described_class.new
      expect(Legion::Audit::Archiver).not_to receive(:archive_to_warm)
      actor.run_archival
    end
  end
end
