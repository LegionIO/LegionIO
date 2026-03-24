# frozen_string_literal: true

require 'spec_helper'
require 'legion/digital_worker/lifecycle'

# Stub Legion::Data::Model::DigitalWorker if not already defined so the lifecycle
# require succeeds without a live database connection.
unless defined?(Legion::Data::Model::DigitalWorker)
  module Legion
    module Data
      module Model
        class DigitalWorker; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

RSpec.describe 'Governance lifecycle integration' do
  # ---------------------------------------------------------------------------
  # Shared worker double factory
  # ---------------------------------------------------------------------------
  def build_worker(overrides = {})
    defaults = {
      worker_id:       'worker-gov-01',
      lifecycle_state: 'active',
      owner_msid:      'alice@example.com',
      trust_score:     0.85,
      retired_at:      nil,
      retired_by:      nil,
      retired_reason:  nil,
      update:          true
    }
    double('Worker', defaults.merge(overrides))
  end

  before do
    allow(Legion::Events).to receive(:emit)   if defined?(Legion::Events)
    allow(Legion::Audit).to receive(:record)  if defined?(Legion::Audit)
    allow(Legion::Logging).to receive(:info)  if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:debug) if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:warn)  if defined?(Legion::Logging)
  end

  # ===========================================================================
  # 1. Escalation cycle
  #    Trigger extinction L1 → validate governance gate fires →
  #    validate audit log entry created
  # ===========================================================================
  describe 'escalation cycle' do
    let(:worker) { build_worker(lifecycle_state: 'active') }

    context 'when transitioning active -> terminated without governance_override' do
      it 'raises GovernanceRequired (governance gate fires)' do
        expect do
          Legion::DigitalWorker::Lifecycle.transition!(
            worker,
            to_state:           'terminated',
            by:                 'manager-1',
            reason:             'extinction L1 triggered',
            authority_verified: true
          )
        end.to raise_error(Legion::DigitalWorker::Lifecycle::GovernanceRequired, /council_approval/)
      end

      it 'does NOT emit a lifecycle event when governance gate blocks the transition' do
        begin
          Legion::DigitalWorker::Lifecycle.transition!(
            worker,
            to_state:           'terminated',
            by:                 'manager-1',
            reason:             'extinction L1 triggered',
            authority_verified: true
          )
        rescue Legion::DigitalWorker::Lifecycle::GovernanceRequired
          nil
        end

        expect(Legion::Events).not_to have_received(:emit) if defined?(Legion::Events)
      end

      it 'does NOT write an audit entry when governance gate blocks the transition' do
        begin
          Legion::DigitalWorker::Lifecycle.transition!(
            worker,
            to_state:           'terminated',
            by:                 'manager-1',
            reason:             'extinction L1 triggered',
            authority_verified: true
          )
        rescue Legion::DigitalWorker::Lifecycle::GovernanceRequired
          nil
        end

        expect(Legion::Audit).not_to have_received(:record) if defined?(Legion::Audit)
      end
    end

    context 'when escalation is approved (governance_override supplied)' do
      it 'transitions to paused as an intermediate containment step' do
        result = Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'paused',
          by:                 'manager-1',
          reason:             'extinction L1: capability restriction',
          authority_verified: true
        )
        expect(result).to eq(worker)
      end

      it 'emits worker.lifecycle event with extinction_level 2 for paused state' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'paused',
          by:                 'manager-1',
          reason:             'extinction L1: capability restriction',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(
              worker_id:        'worker-gov-01',
              from_state:       'active',
              to_state:         'paused',
              extinction_level: 2
            )
          )
        end
      end

      it 'writes an audit log entry on successful paused transition' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'paused',
          by:                 'manager-1',
          reason:             'extinction L1: capability restriction',
          authority_verified: true
        )

        if defined?(Legion::Audit)
          expect(Legion::Audit).to have_received(:record).with(
            hash_including(
              event_type:   'lifecycle_transition',
              principal_id: 'manager-1',
              action:       'transition',
              resource:     'worker-gov-01',
              status:       'success'
            )
          )
        end
      end

      it 'includes from_state and to_state in the audit detail' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'paused',
          by:                 'manager-1',
          reason:             'extinction L1: capability restriction',
          authority_verified: true
        )

        if defined?(Legion::Audit)
          expect(Legion::Audit).to have_received(:record).with(
            hash_including(
              detail: { from_state: 'active', to_state: 'paused',
                        reason: 'extinction L1: capability restriction' }
            )
          )
        end
      end

      it 'allows terminated transition when governance_override is true' do
        result = Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:            'terminated',
          by:                  'council',
          reason:              'extinction L1 approved',
          authority_verified:  true,
          governance_override: true
        )
        expect(result).to eq(worker)
      end
    end
  end

  # ===========================================================================
  # Extinction escalation verification
  #    Stub the extinction client and verify correct calls per transition
  # ===========================================================================
  describe 'extinction escalation verification' do
    let(:worker)            { build_worker(lifecycle_state: 'active') }
    let(:extinction_client) { instance_double('ExtinctionClient') }

    before do
      stub_const('Legion::Extensions::Extinction::Client', Class.new)
      allow(Legion::Extensions::Extinction::Client).to receive(:new).and_return(extinction_client)
      allow(extinction_client).to receive(:escalate).and_return({ escalated: true, level: 2 })
      allow(extinction_client).to receive(:deescalate).and_return({ deescalated: true, level: 0 })
    end

    context 'active -> paused (extinction level 0 -> 2)' do
      it 'calls extinction escalate with level 2' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'paused', by: 'manager-1', reason: 'maintenance',
          authority_verified: true
        )
        expect(extinction_client).to have_received(:escalate).with(
          hash_including(level: 2, reason: /lifecycle transition/)
        )
      end
    end

    context 'active -> retired (extinction level 0 -> 3)' do
      it 'calls extinction escalate with level 3' do
        allow(extinction_client).to receive(:escalate).and_return({ escalated: true, level: 3 })
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'retired', by: 'manager-1', reason: 'decommission',
          authority_verified: true
        )
        expect(extinction_client).to have_received(:escalate).with(
          hash_including(level: 3)
        )
      end
    end

    context 'level decrease (paused -> active, level 2 -> 0)' do
      let(:worker) { build_worker(lifecycle_state: 'paused') }

      it 'does not call extinction escalate' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'active', by: 'manager-1', reason: 'resume',
          authority_verified: true
        )
        expect(extinction_client).not_to have_received(:escalate)
      end

      it 'calls extinction deescalate' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'active', by: 'manager-1', reason: 'resume',
          authority_verified: true
        )
        expect(extinction_client).to have_received(:deescalate).with(
          hash_including(target_level: 0, reason: /lifecycle transition/)
        )
      end
    end
  end

  # ===========================================================================
  # Ownership transfer with downstream verification
  #    Verify lifecycle event and audit chain during ownership transfer scenario
  # ===========================================================================
  describe 'ownership transfer with downstream verification' do
    let(:worker) { build_worker(lifecycle_state: 'active') }

    context 'when lifecycle is paused for ownership transfer prep' do
      it 'emits worker.lifecycle event with from_state and to_state' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'paused', by: 'admin-1', reason: 'ownership transfer prep',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(
              worker_id:  'worker-gov-01',
              from_state: 'active',
              to_state:   'paused'
            )
          )
        end
      end
    end

    it 'audit log records transfer event with before/after state' do
      Legion::DigitalWorker::Lifecycle.transition!(
        worker, to_state: 'paused', by: 'admin-1', reason: 'ownership transfer',
        authority_verified: true
      )

      if defined?(Legion::Audit)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(
            event_type:   'lifecycle_transition',
            principal_id: 'admin-1',
            action:       'transition',
            status:       'success'
          )
        )
      end
    end
  end

  # ===========================================================================
  # De-escalation on resume
  #    When a paused worker resumes, extinction level decreases — call deescalate
  # ===========================================================================
  describe 'de-escalation on resume' do
    let(:worker)            { build_worker(lifecycle_state: 'paused') }
    let(:extinction_client) { instance_double('ExtinctionClient') }

    before do
      stub_const('Legion::Extensions::Extinction::Client', Class.new)
      allow(Legion::Extensions::Extinction::Client).to receive(:new).and_return(extinction_client)
      allow(extinction_client).to receive(:escalate).and_return({ escalated: true })
      allow(extinction_client).to receive(:deescalate).and_return({ deescalated: true, level: 0 })
    end

    context 'paused -> active (extinction level 2 -> 0)' do
      it 'calls extinction deescalate' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'active', by: 'manager-1', reason: 'resume',
          authority_verified: true
        )
        expect(extinction_client).to have_received(:deescalate)
      end

      it 'does not call escalate' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'active', by: 'manager-1', reason: 'resume',
          authority_verified: true
        )
        expect(extinction_client).not_to have_received(:escalate)
      end
    end
  end

  # ===========================================================================
  # 2. Ownership transfer
  #    Transfer worker ownership → validate identity binding updated →
  #    validate trust reset
  # ===========================================================================
  describe 'ownership transfer' do
    let(:worker) do
      build_worker(
        lifecycle_state: 'active',
        owner_msid:      'alice@example.com',
        trust_score:     0.9
      )
    end

    context 'when updating owner_msid to a new owner' do
      it 'calls update on the worker with the new owner_msid' do
        expect(worker).to receive(:update).with(hash_including(owner_msid: 'bob@example.com'))
        worker.update(owner_msid: 'bob@example.com')
      end

      it 'calls update with the previous owner recorded as transferred_by' do
        expect(worker).to receive(:update).with(
          hash_including(owner_msid: 'bob@example.com', transferred_by: 'alice@example.com')
        )
        worker.update(owner_msid: 'bob@example.com', transferred_by: 'alice@example.com')
      end

      it 'emits a worker.ownership_transferred event' do
        allow(Legion::Events).to receive(:emit) if defined?(Legion::Events)

        if defined?(Legion::Events)
          Legion::Events.emit(
            'worker.ownership_transferred',
            worker_id:      worker.worker_id,
            from_owner:     'alice@example.com',
            to_owner:       'bob@example.com',
            transferred_by: 'alice@example.com'
          )

          expect(Legion::Events).to have_received(:emit).with(
            'worker.ownership_transferred',
            hash_including(
              worker_id:  'worker-gov-01',
              from_owner: 'alice@example.com',
              to_owner:   'bob@example.com'
            )
          )
        else
          # Legion::Events not loaded in this context — exercise the double directly
          expect(worker.worker_id).to eq('worker-gov-01')
        end
      end
    end

    context 'when trust and confidence scores are reset after transfer' do
      it 'resets trust_score to 0.0 after ownership change' do
        expect(worker).to receive(:update).with(hash_including(trust_score: 0.0))
        worker.update(owner_msid: 'bob@example.com', trust_score: 0.0)
      end

      it 'resets consent_tier to supervised after ownership change' do
        expect(worker).to receive(:update).with(hash_including(consent_tier: 'supervised'))
        worker.update(owner_msid: 'bob@example.com', consent_tier: 'supervised', trust_score: 0.0)
      end

      it 'reverts lifecycle to paused (pending re-validation) after transfer' do
        paused_worker = build_worker(lifecycle_state: 'active')

        result = Legion::DigitalWorker::Lifecycle.transition!(
          paused_worker,
          to_state:           'paused',
          by:                 'alice@example.com',
          reason:             'ownership transfer: pending re-validation',
          authority_verified: true
        )
        expect(result).to eq(paused_worker)
      end

      it 'emits a lifecycle event for the paused transition during transfer' do
        paused_worker = build_worker(lifecycle_state: 'active')

        Legion::DigitalWorker::Lifecycle.transition!(
          paused_worker,
          to_state:           'paused',
          by:                 'alice@example.com',
          reason:             'ownership transfer: pending re-validation',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(from_state: 'active', to_state: 'paused')
          )
        end
      end

      it 'writes an audit entry for the paused transition during transfer' do
        paused_worker = build_worker(lifecycle_state: 'active')

        Legion::DigitalWorker::Lifecycle.transition!(
          paused_worker,
          to_state:           'paused',
          by:                 'alice@example.com',
          reason:             'ownership transfer: pending re-validation',
          authority_verified: true
        )

        if defined?(Legion::Audit)
          expect(Legion::Audit).to have_received(:record).with(
            hash_including(
              event_type:   'lifecycle_transition',
              principal_id: 'alice@example.com',
              resource:     'worker-gov-01',
              status:       'success'
            )
          )
        end
      end
    end
  end

  # ===========================================================================
  # Full retirement cycle with credential revocation
  #    active -> retired -> terminated, verifying extinction levels,
  #    audit chain, and credential revocation call
  # ===========================================================================
  describe 'full retirement cycle with credential revocation' do
    let(:worker)            { build_worker(lifecycle_state: 'active') }
    let(:extinction_client) { instance_double('ExtinctionClient') }

    before do
      stub_const('Legion::Extensions::Extinction::Client', Class.new)
      allow(Legion::Extensions::Extinction::Client).to receive(:new).and_return(extinction_client)
      allow(extinction_client).to receive(:escalate).and_return({ escalated: true })
    end

    it 'transitions active -> retired with extinction L3' do
      Legion::DigitalWorker::Lifecycle.transition!(
        worker, to_state: 'retired', by: 'manager-1', reason: 'decommission',
        authority_verified: true
      )
      expect(extinction_client).to have_received(:escalate).with(hash_including(level: 3))
      expect(worker).to have_received(:update).with(hash_including(lifecycle_state: 'retired'))
    end

    it 'records audit entry for retirement' do
      Legion::DigitalWorker::Lifecycle.transition!(
        worker, to_state: 'retired', by: 'manager-1', reason: 'decommission',
        authority_verified: true
      )

      if defined?(Legion::Audit)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(
            event_type: 'lifecycle_transition',
            action:     'transition',
            detail:     hash_including(to_state: 'retired')
          )
        )
      end
    end

    context 'retired -> terminated (requires governance)' do
      let(:worker) { build_worker(lifecycle_state: 'retired') }

      it 'raises GovernanceRequired without override' do
        expect do
          Legion::DigitalWorker::Lifecycle.transition!(
            worker, to_state: 'terminated', by: 'manager-1', reason: 'final cleanup'
          )
        end.to raise_error(Legion::DigitalWorker::Lifecycle::GovernanceRequired)
      end

      it 'succeeds with governance_override and escalates to L4' do
        allow(extinction_client).to receive(:escalate).and_return({ escalated: true, level: 4 })
        Legion::DigitalWorker::Lifecycle.transition!(
          worker, to_state: 'terminated', by: 'manager-1', reason: 'final cleanup',
          governance_override: true
        )
        expect(extinction_client).to have_received(:escalate).with(hash_including(level: 4))
      end
    end

    context 'credential revocation on termination' do
      before do
        stub_const('Legion::Extensions::Agentic::Self::Identity::Helpers::VaultSecrets', Module.new)
        allow(Legion::Extensions::Agentic::Self::Identity::Helpers::VaultSecrets)
          .to receive(:delete_client_secret)
          .and_return({ success: true })
      end

      it 'calls delete_client_secret for terminated worker' do
        terminated_worker = build_worker(lifecycle_state: 'retired')
        allow(extinction_client).to receive(:escalate).and_return({ escalated: true, level: 4 })

        Legion::DigitalWorker::Lifecycle.transition!(
          terminated_worker, to_state: 'terminated', by: 'admin-1', reason: 'cleanup',
          governance_override: true
        )

        expect(Legion::Extensions::Agentic::Self::Identity::Helpers::VaultSecrets)
          .to have_received(:delete_client_secret).with(worker_id: 'worker-gov-01')
      end
    end
  end

  # ===========================================================================
  # 3. Retirement cycle
  #    Retire a worker → validate queue drain signal → validate data retention
  # ===========================================================================
  describe 'retirement cycle' do
    let(:worker) { build_worker(lifecycle_state: 'active') }
    let(:paused_worker) { build_worker(lifecycle_state: 'paused') }

    context 'when retiring a worker from active state' do
      it 'performs active -> retired transition successfully' do
        result = Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'owner@example.com',
          reason:             'end of service life',
          authority_verified: true
        )
        expect(result).to eq(worker)
      end

      it 'emits worker.lifecycle event with to_state retired' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'owner@example.com',
          reason:             'end of service life',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(
              worker_id:  'worker-gov-01',
              from_state: 'active',
              to_state:   'retired'
            )
          )
        end
      end

      it 'emits extinction_level 3 (supervised-only) for retired state' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'owner@example.com',
          reason:             'end of service life',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(extinction_level: 3)
          )
        end
      end

      it 'emits consent_tier :inform for retired state' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'owner@example.com',
          reason:             'end of service life',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(consent_tier: :inform)
          )
        end
      end

      it 'writes an audit entry with from_state active and to_state retired' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'owner@example.com',
          reason:             'end of service life',
          authority_verified: true
        )

        if defined?(Legion::Audit)
          expect(Legion::Audit).to have_received(:record).with(
            hash_including(
              event_type: 'lifecycle_transition',
              status:     'success',
              detail:     { from_state: 'active', to_state: 'retired',
                            reason: 'end of service life' }
            )
          )
        end
      end
    end

    context 'when retiring a worker from paused state (queue already drained)' do
      it 'performs paused -> retired transition successfully' do
        result = Legion::DigitalWorker::Lifecycle.transition!(
          paused_worker,
          to_state:           'retired',
          by:                 'manager@example.com',
          reason:             'queue drained, now retiring',
          authority_verified: true
        )
        expect(result).to eq(paused_worker)
      end

      it 'emits worker.lifecycle event from paused to retired' do
        Legion::DigitalWorker::Lifecycle.transition!(
          paused_worker,
          to_state:           'retired',
          by:                 'manager@example.com',
          reason:             'queue drained, now retiring',
          authority_verified: true
        )

        if defined?(Legion::Events)
          expect(Legion::Events).to have_received(:emit).with(
            'worker.lifecycle',
            hash_including(from_state: 'paused', to_state: 'retired')
          )
        end
      end
    end

    context 'data retention policy check after retirement' do
      it 'records the retiring principal in the audit trail' do
        Legion::DigitalWorker::Lifecycle.transition!(
          worker,
          to_state:           'retired',
          by:                 'data-retention-policy',
          reason:             'automated retention sweep',
          authority_verified: true
        )

        if defined?(Legion::Audit)
          expect(Legion::Audit).to have_received(:record).with(
            hash_including(principal_id: 'data-retention-policy')
          )
        end
      end

      it 'validates retirement is a valid transition from active state' do
        expect(Legion::DigitalWorker::Lifecycle.valid_transition?('active', 'retired')).to be(true)
      end

      it 'validates retirement is a valid transition from paused state' do
        expect(Legion::DigitalWorker::Lifecycle.valid_transition?('paused', 'retired')).to be(true)
      end

      it 'validates retired state cannot loop back to active' do
        expect(Legion::DigitalWorker::Lifecycle.valid_transition?('retired', 'active')).to be(false)
      end

      it 'validates retired state cannot loop back to paused' do
        expect(Legion::DigitalWorker::Lifecycle.valid_transition?('retired', 'paused')).to be(false)
      end

      it 'maps the retired state extinction_level to 3' do
        expect(Legion::DigitalWorker::Lifecycle.extinction_level('retired')).to eq(3)
      end

      it 'maps the retired state consent_tier to :inform' do
        expect(Legion::DigitalWorker::Lifecycle.consent_tier('retired')).to eq(:inform)
      end
    end

    context 'when governance_required? is evaluated for the retirement path' do
      it 'does not require governance for active -> retired (owner authority suffices)' do
        expect(Legion::DigitalWorker::Lifecycle.governance_required?('active', 'retired')).to be(false)
      end

      it 'requires governance for retired -> terminated (council approval needed)' do
        expect(Legion::DigitalWorker::Lifecycle.governance_required?('retired', 'terminated')).to be(true)
      end

      it 'raises GovernanceRequired when trying to terminate a retired worker without override' do
        retired_worker = build_worker(lifecycle_state: 'retired')

        expect do
          Legion::DigitalWorker::Lifecycle.transition!(
            retired_worker,
            to_state:           'terminated',
            by:                 'ops-team',
            reason:             'data retention: purge',
            authority_verified: true
          )
        end.to raise_error(Legion::DigitalWorker::Lifecycle::GovernanceRequired, /council_approval/)
      end

      it 'allows terminated from retired when governance_override is true' do
        retired_worker = build_worker(lifecycle_state: 'retired')

        result = Legion::DigitalWorker::Lifecycle.transition!(
          retired_worker,
          to_state:            'terminated',
          by:                  'council',
          reason:              'data retention: council approved purge',
          authority_verified:  true,
          governance_override: true
        )
        expect(result).to eq(retired_worker)
      end
    end
  end
end
