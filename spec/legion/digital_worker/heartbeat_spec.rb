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

require 'legion/digital_worker'

RSpec.describe Legion::DigitalWorker do
  describe '.heartbeat' do
    let(:worker) { double('Worker', worker_id: 'w1') }

    it 'updates last_heartbeat_at and health_status' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'w1').and_return(worker)
      expect(worker).to receive(:update).with(hash_including(
                                                health_status:     'healthy',
                                                last_heartbeat_at: an_instance_of(Time)
                                              ))
      described_class.heartbeat(worker_id: 'w1')
    end

    it 'includes health_node when provided' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'w1').and_return(worker)
      expect(worker).to receive(:update).with(hash_including(health_node: 'node-1'))
      described_class.heartbeat(worker_id: 'w1', health_node: 'node-1')
    end

    it 'accepts custom health_status' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'w1').and_return(worker)
      expect(worker).to receive(:update).with(hash_including(health_status: 'degraded'))
      described_class.heartbeat(worker_id: 'w1', health_status: 'degraded')
    end

    it 'returns nil when worker not found' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'missing').and_return(nil)
      expect(described_class.heartbeat(worker_id: 'missing')).to be_nil
    end
  end

  describe '.detect_orphans' do
    let(:stale_worker) do
      double('Worker', worker_id: 'w-stale', lifecycle_state: 'active',
                       last_heartbeat_at: Time.now.utc - 864_000, owner_msid: 'user1')
    end
    let(:nil_heartbeat_worker) do
      double('Worker', worker_id: 'w-nil', lifecycle_state: 'active',
                       last_heartbeat_at: nil, owner_msid: 'user2')
    end
    let(:healthy_worker) do
      double('Worker', worker_id: 'w-ok', lifecycle_state: 'active',
                       last_heartbeat_at: Time.now.utc, owner_msid: 'user3')
    end
    let(:dataset) { double('dataset') }

    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:where)
        .with(lifecycle_state: 'active').and_return(dataset)
      allow(dataset).to receive(:all).and_return([stale_worker, nil_heartbeat_worker, healthy_worker])
    end

    it 'returns workers with stale or nil heartbeats' do
      orphans = described_class.detect_orphans(stale_days: 7)
      expect(orphans).to contain_exactly(stale_worker, nil_heartbeat_worker)
    end

    it 'respects custom stale_days' do
      orphans = described_class.detect_orphans(stale_days: 20)
      expect(orphans.map(&:worker_id)).to include('w-nil')
    end

    it 'excludes healthy workers' do
      orphans = described_class.detect_orphans(stale_days: 7)
      expect(orphans.map(&:worker_id)).not_to include('w-ok')
    end
  end

  describe '.pause_orphans!' do
    let(:stale_worker) do
      double('Worker', worker_id: 'w-stale', lifecycle_state: 'active',
                       last_heartbeat_at: nil, owner_msid: 'user1',
                       retired_at: nil, retired_by: nil, retired_reason: nil)
    end
    let(:dataset) { double('dataset') }

    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:where)
        .with(lifecycle_state: 'active').and_return(dataset)
      allow(dataset).to receive(:all).and_return([stale_worker])
      hide_const('Legion::Events') if defined?(Legion::Events)
      hide_const('Legion::Audit') if defined?(Legion::Audit)
      hide_const('Legion::Extensions::Governance') if defined?(Legion::Extensions::Governance)
    end

    it 'transitions orphaned workers to paused' do
      expect(stale_worker).to receive(:update).with(hash_including(lifecycle_state: 'paused'))
      described_class.pause_orphans!(stale_days: 7)
    end
  end
end
