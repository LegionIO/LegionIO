# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Data::Model::DigitalWorker)
  module Legion
    module Data
      module Model
        class DigitalWorker; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

require 'legion/digital_worker/registry'

RSpec.describe Legion::DigitalWorker::Registry do
  before(:each) do
    described_class.clear_local_workers! if described_class.respond_to?(:clear_local_workers!)
  end

  describe '.local_worker_ids' do
    it 'returns empty array initially' do
      expect(described_class.local_worker_ids).to eq([])
    end
  end

  describe '.clear_local_workers!' do
    it 'empties the local workers set' do
      described_class.clear_local_workers!
      expect(described_class.local_worker_ids).to eq([])
    end
  end

  describe 'worker tracking via validate_execution!' do
    let(:worker) do
      double('worker', active?: true, consent_tier: 'autonomous', lifecycle_state: 'active')
    end

    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).and_return(worker)
    end

    it 'adds worker_id to local_worker_ids after successful validation' do
      described_class.validate_execution!(worker_id: 'w-123')
      expect(described_class.local_worker_ids).to include('w-123')
    end

    it 'does not duplicate worker_ids on repeated validations' do
      described_class.validate_execution!(worker_id: 'w-123')
      described_class.validate_execution!(worker_id: 'w-123')
      expect(described_class.local_worker_ids.count('w-123')).to eq(1)
    end
  end

  describe 'DigitalWorker.active_local_ids' do
    it 'delegates to Registry.local_worker_ids' do
      require 'legion/digital_worker'
      expect(Legion::DigitalWorker.active_local_ids).to eq(described_class.local_worker_ids)
    end
  end

  describe 'CONSENT_HIERARCHY' do
    it 'uses inform (not notify) to match Lifecycle::CONSENT_MAPPING' do
      expect(described_class::CONSENT_HIERARCHY).to include('inform')
      expect(described_class::CONSENT_HIERARCHY).not_to include('notify')
    end

    it 'orders tiers from most restrictive to most autonomous' do
      expect(described_class::CONSENT_HIERARCHY).to eq(%w[supervised consult inform autonomous])
    end
  end

  describe '.consent_sufficient?' do
    it 'returns true when current tier meets required tier' do
      expect(described_class.consent_sufficient?('autonomous', 'inform')).to be true
    end

    it 'returns false when current tier is below required tier' do
      expect(described_class.consent_sufficient?('supervised', 'autonomous')).to be false
    end

    it 'returns true when tiers are equal' do
      expect(described_class.consent_sufficient?('inform', 'inform')).to be true
    end
  end

  describe 'thread safety' do
    let(:worker) do
      double('worker', active?: true, consent_tier: 'autonomous', lifecycle_state: 'active')
    end

    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).and_return(worker)
    end

    it 'handles concurrent validate_execution! calls without losing worker IDs' do
      threads = 10.times.map do |i|
        Thread.new { described_class.validate_execution!(worker_id: "w-#{i}") }
      end
      threads.each(&:join)
      expect(described_class.local_worker_ids.sort).to eq((0..9).map { |i| "w-#{i}" }.sort)
    end
  end
end
