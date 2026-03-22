# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/failover_command'
require 'legion/region/failover'

RSpec.describe Legion::CLI::Failover do
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
    allow(Legion::CLI::Connection).to receive(:ensure_settings)
  end

  after do
    Legion::Settings.loader.settings[:region] = @saved_region
  end

  describe 'promote --dry-run' do
    it 'does not change the primary setting' do
      allow(Legion::Region::Failover).to receive(:replication_lag).and_return(1.0)
      begin
        described_class.start(%w[promote --region us-west-2 --dry-run])
      rescue SystemExit
        nil
      end
      expect(Legion::Settings.loader.settings[:region][:primary]).to eq('us-east-2')
    end
  end

  describe 'promote with unknown region' do
    it 'raises SystemExit for unknown region' do
      expect { described_class.start(%w[promote --region eu-central-1]) }
        .to raise_error(SystemExit)
    end
  end

  describe 'status' do
    it 'runs without error' do
      expect { described_class.start(%w[status --json]) }.not_to raise_error
    end

    it 'includes current region in JSON output' do
      expect { described_class.start(%w[status --json]) }.to output(/us-east-2/).to_stdout
    end
  end
end
