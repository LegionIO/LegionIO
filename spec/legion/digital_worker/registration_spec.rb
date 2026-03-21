# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

unless defined?(Legion::Data::Model::DigitalWorker)
  module Legion
    module Data
      module Model
        class DigitalWorker; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

require 'legion/digital_worker/lifecycle'
require 'legion/digital_worker/registration'

RSpec.describe Legion::DigitalWorker::Registration do
  let(:worker_id) { SecureRandom.uuid }

  let(:worker_double) do
    double(
      'Worker',
      worker_id:       worker_id,
      name:            'TestBot',
      lifecycle_state: 'pending_approval',
      risk_tier:       'high',
      created_at:      Time.now.utc - 3600,
      update:          true,
      retired_at:      nil,
      retired_by:      nil,
      retired_reason:  nil,
      to_hash:         { worker_id: worker_id, name: 'TestBot', lifecycle_state: 'pending_approval' }
    )
  end

  let(:active_worker_double) do
    double(
      'Worker',
      worker_id:       worker_id,
      name:            'TestBot',
      lifecycle_state: 'active',
      risk_tier:       'high',
      created_at:      Time.now.utc - 3600,
      update:          true,
      retired_at:      nil,
      retired_by:      nil,
      retired_reason:  nil,
      to_hash:         { worker_id: worker_id, name: 'TestBot', lifecycle_state: 'active' }
    )
  end

  before do
    allow(Legion::Events).to receive(:emit) if defined?(Legion::Events)
    allow(Legion::Logging).to receive(:info)  if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:warn)  if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:debug) if defined?(Legion::Logging)
  end

  describe '.approval_required?' do
    it 'returns true for high tier' do
      expect(described_class.approval_required?('high')).to be(true)
    end

    it 'returns true for critical tier' do
      expect(described_class.approval_required?('critical')).to be(true)
    end

    it 'returns false for medium tier' do
      expect(described_class.approval_required?('medium')).to be(false)
    end

    it 'returns false for low tier' do
      expect(described_class.approval_required?('low')).to be(false)
    end

    it 'returns false for an empty string' do
      expect(described_class.approval_required?('')).to be(false)
    end

    it 'handles symbol input by converting to string' do
      expect(described_class.approval_required?(:high)).to be(true)
    end
  end

  describe '.register' do
    let(:base_attrs) do
      {
        name:           'TestBot',
        extension_name: 'lex-testbot',
        entra_app_id:   'app-123',
        owner_msid:     'owner@example.com',
        risk_tier:      'low'
      }
    end

    context 'with a low risk tier' do
      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:create).and_return(
          double('Worker',
                 worker_id: worker_id, name: 'TestBot', lifecycle_state: 'bootstrap',
                 risk_tier: 'low', created_at: Time.now.utc, update: true,
                 retired_at: nil, retired_by: nil, retired_reason: nil)
        )
      end

      it 'creates the worker in bootstrap state' do
        expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
          hash_including(lifecycle_state: 'bootstrap')
        )
        described_class.register(base_attrs)
      end

      it 'does not require approval' do
        expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
          hash_including(lifecycle_state: 'bootstrap')
        )
        described_class.register(base_attrs)
      end
    end

    context 'with a high risk tier' do
      let(:high_attrs) { base_attrs.merge(risk_tier: 'high') }

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:create).and_return(worker_double)
        allow(Legion::DigitalWorker::Airb).to receive(:create_intake).and_return('airb-mock-001') if defined?(Legion::DigitalWorker::Airb)
      end

      it 'creates the worker in pending_approval state' do
        expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
          hash_including(lifecycle_state: 'pending_approval')
        )
        described_class.register(high_attrs)
      end

      it 'returns the created worker' do
        result = described_class.register(high_attrs)
        expect(result).to eq(worker_double)
      end
    end

    context 'with a critical risk tier' do
      let(:critical_attrs) { base_attrs.merge(risk_tier: 'critical') }

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:create).and_return(
          double('Worker',
                 worker_id: worker_id, name: 'CritBot', lifecycle_state: 'pending_approval',
                 risk_tier: 'critical', created_at: Time.now.utc, update: true,
                 retired_at: nil, retired_by: nil, retired_reason: nil)
        )
      end

      it 'creates the worker in pending_approval state' do
        expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
          hash_including(lifecycle_state: 'pending_approval')
        )
        described_class.register(critical_attrs)
      end
    end

    it 'sets consent_tier to supervised by default' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:create).and_return(worker_double)
      expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
        hash_including(consent_tier: 'supervised')
      )
      described_class.register(base_attrs)
    end

    it 'sets trust_score to 0.0 by default' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:create).and_return(worker_double)
      expect(Legion::Data::Model::DigitalWorker).to receive(:create).with(
        hash_including(trust_score: 0.0)
      )
      described_class.register(base_attrs)
    end
  end

  describe '.pending_approvals' do
    it 'returns workers with pending_approval state' do
      dataset = [worker_double]
      allow(Legion::Data::Model::DigitalWorker).to receive(:where).with(lifecycle_state: 'pending_approval').and_return(double(all: dataset))
      expect(described_class.pending_approvals).to eq(dataset)
    end

    it 'returns an empty array when DigitalWorker model is not defined' do
      hide_const('Legion::Data::Model::DigitalWorker')
      expect(described_class.pending_approvals).to eq([])
    end
  end

  describe '.approve' do
    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(worker_double)
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!).and_return(active_worker_double)
      allow(Legion::Audit).to receive(:record) if defined?(Legion::Audit)
    end

    it 'calls Lifecycle.transition! with to_state active' do
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker_double,
        hash_including(to_state: 'active')
      ).and_return(active_worker_double)
      described_class.approve(worker_id, approver: 'admin@example.com')
    end

    it 'passes the approver as the by argument' do
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker_double,
        hash_including(by: 'admin@example.com')
      ).and_return(active_worker_double)
      described_class.approve(worker_id, approver: 'admin@example.com')
    end

    it 'passes notes as the reason' do
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker_double,
        hash_including(reason: 'LGTM')
      ).and_return(active_worker_double)
      described_class.approve(worker_id, approver: 'admin@example.com', notes: 'LGTM')
    end

    it 'raises ArgumentError when worker is not found' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'bad-id').and_return(nil)
      expect { described_class.approve('bad-id', approver: 'admin') }.to raise_error(ArgumentError, /worker not found/)
    end

    it 'raises ArgumentError when worker is not pending approval' do
      non_pending = double('Worker', worker_id: worker_id, lifecycle_state: 'active')
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(non_pending)
      expect { described_class.approve(worker_id, approver: 'admin') }.to raise_error(ArgumentError, /not pending approval/)
    end
  end

  describe '.reject' do
    before do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(worker_double)
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!).and_return(
        double('Worker', worker_id: worker_id, name: 'TestBot', lifecycle_state: 'rejected',
               update: true, retired_at: nil, retired_by: nil, retired_reason: nil)
      )
      allow(Legion::Audit).to receive(:record) if defined?(Legion::Audit)
    end

    it 'calls Lifecycle.transition! with to_state rejected' do
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker_double,
        hash_including(to_state: 'rejected')
      )
      described_class.reject(worker_id, approver: 'admin@example.com', reason: 'policy violation')
    end

    it 'passes the approver and reason' do
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker_double,
        hash_including(by: 'admin@example.com', reason: 'policy violation')
      )
      described_class.reject(worker_id, approver: 'admin@example.com', reason: 'policy violation')
    end

    it 'raises ArgumentError when worker is not found' do
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'no-such-id').and_return(nil)
      expect { described_class.reject('no-such-id', approver: 'admin', reason: 'nope') }
        .to raise_error(ArgumentError, /worker not found/)
    end
  end

  describe '.escalate' do
    context 'when worker is pending and has exceeded timeout' do
      let(:old_worker) do
        double('Worker',
               worker_id:       worker_id,
               lifecycle_state: 'pending_approval',
               created_at:      Time.now.utc - Legion::DigitalWorker::Registration::APPROVAL_TIMEOUT_SECONDS - 3600)
      end

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(old_worker)
      end

      it 'returns escalated: true' do
        result = described_class.escalate(worker_id)
        expect(result[:escalated]).to be(true)
      end

      it 'includes the worker_id in the result' do
        result = described_class.escalate(worker_id)
        expect(result[:worker_id]).to eq(worker_id)
      end
    end

    context 'when worker is pending but within timeout' do
      let(:recent_worker) do
        double('Worker',
               worker_id:       worker_id,
               lifecycle_state: 'pending_approval',
               created_at:      Time.now.utc - 3600)
      end

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(recent_worker)
      end

      it 'returns escalated: false' do
        result = described_class.escalate(worker_id)
        expect(result[:escalated]).to be(false)
      end

      it 'includes remaining_seconds in the result' do
        result = described_class.escalate(worker_id)
        expect(result[:remaining_seconds]).to be > 0
      end
    end

    context 'when worker is not found' do
      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'missing').and_return(nil)
      end

      it 'returns escalated: false with a reason' do
        result = described_class.escalate('missing')
        expect(result[:escalated]).to be(false)
        expect(result[:reason]).to eq('worker not found')
      end
    end

    context 'when worker is not pending' do
      let(:active_w) { double('Worker', worker_id: worker_id, lifecycle_state: 'active', created_at: Time.now.utc - 1000) }

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(active_w)
      end

      it 'returns escalated: false' do
        result = described_class.escalate(worker_id)
        expect(result[:escalated]).to be(false)
        expect(result[:reason]).to eq('not pending approval')
      end
    end
  end
end
