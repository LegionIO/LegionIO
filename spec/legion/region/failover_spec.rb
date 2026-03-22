# frozen_string_literal: true

require 'spec_helper'
require 'legion/region/failover'

RSpec.describe Legion::Region::Failover do
  before do
    Legion::Settings.loader.settings[:region] ||= {}
    @saved_region = Legion::Settings.loader.settings[:region].dup
    Legion::Settings.loader.settings[:region] = {
      current:          'us-east-2',
      primary:          'us-east-2',
      failover:         'us-west-2',
      peers:            %w[us-east-2 us-west-2],
      default_affinity: 'prefer_local',
      data_residency:   {}
    }
  end

  after do
    Legion::Settings.loader.settings[:region] = @saved_region
  end

  describe '.validate_target!' do
    it 'accepts a known peer region' do
      expect { described_class.validate_target!('us-west-2') }.not_to raise_error
    end

    it 'accepts the failover region' do
      Legion::Settings.loader.settings[:region][:peers] = []
      expect { described_class.validate_target!('us-west-2') }.not_to raise_error
    end

    it 'raises UnknownRegionError for unknown region' do
      expect { described_class.validate_target!('eu-west-1') }
        .to raise_error(Legion::Region::Failover::UnknownRegionError, /eu-west-1/)
    end
  end

  describe '.replication_lag' do
    context 'when Legion::Data is available' do
      let(:fake_db) { instance_double('Sequel::Database') }

      before do
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
      end

      it 'returns the lag in seconds' do
        allow(fake_db).to receive(:fetch).and_return([{ lag: 2.5 }])
        expect(described_class.replication_lag).to eq(2.5)
      end

      it 'returns nil when lag is nil' do
        allow(fake_db).to receive(:fetch).and_return([{ lag: nil }])
        expect(described_class.replication_lag).to be_nil
      end

      it 'returns nil on error' do
        allow(fake_db).to receive(:fetch).and_raise(StandardError, 'connection lost')
        expect(described_class.replication_lag).to be_nil
      end
    end

    context 'when Legion::Data is not available' do
      before do
        hide_const('Legion::Data') if defined?(Legion::Data)
      end

      it 'returns nil' do
        expect(described_class.replication_lag).to be_nil
      end
    end
  end

  describe '.promote!' do
    let(:fake_db) { instance_double('Sequel::Database') }

    before do
      stub_const('Legion::Data', Module.new)
      allow(Legion::Data).to receive(:connection).and_return(fake_db)
      allow(fake_db).to receive(:fetch).and_return([{ lag: 1.0 }])
      allow(Legion::Events).to receive(:emit) if defined?(Legion::Events)
    end

    it 'promotes the target region' do
      result = described_class.promote!(region: 'us-west-2')
      expect(result[:promoted]).to eq('us-west-2')
      expect(result[:previous]).to eq('us-east-2')
    end

    it 'updates settings primary to the new region' do
      described_class.promote!(region: 'us-west-2')
      expect(Legion::Settings.dig(:region, :primary)).to eq('us-west-2')
    end

    it 'returns the replication lag' do
      result = described_class.promote!(region: 'us-west-2')
      expect(result[:lag_seconds]).to eq(1.0)
    end

    it 'emits region.failover event' do
      expect(Legion::Events).to receive(:emit).with('region.failover', from: 'us-east-2', to: 'us-west-2') if defined?(Legion::Events)
      described_class.promote!(region: 'us-west-2')
    end

    it 'raises LagTooHighError when lag exceeds threshold' do
      allow(fake_db).to receive(:fetch).and_return([{ lag: 45.0 }])
      expect { described_class.promote!(region: 'us-west-2') }
        .to raise_error(Legion::Region::Failover::LagTooHighError, /45.0s/)
    end

    it 'raises UnknownRegionError for unknown region' do
      expect { described_class.promote!(region: 'eu-west-1') }
        .to raise_error(Legion::Region::Failover::UnknownRegionError)
    end

    it 'succeeds when lag is nil (no DB)' do
      allow(fake_db).to receive(:fetch).and_return([{ lag: nil }])
      result = described_class.promote!(region: 'us-west-2')
      expect(result[:promoted]).to eq('us-west-2')
      expect(result[:lag_seconds]).to be_nil
    end
  end
end
