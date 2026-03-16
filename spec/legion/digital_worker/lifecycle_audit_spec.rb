# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit'
require 'legion/digital_worker/lifecycle'

RSpec.describe Legion::DigitalWorker::Lifecycle do
  let(:worker) do
    double('Worker',
           worker_id:       'worker-42',
           lifecycle_state: 'active',
           retired_at:      nil,
           retired_by:      nil,
           retired_reason:  nil,
           update:          true)
  end

  before do
    allow(Legion::Events).to receive(:emit) if defined?(Legion::Events)
  end

  describe '.transition! audit integration' do
    context 'when Legion::Audit is defined' do
      before do
        allow(Legion::Audit).to receive(:record)
      end

      it 'calls Legion::Audit.record on successful transition' do
        described_class.transition!(worker, to_state: 'paused', by: 'manager-1',
                                            reason: 'maintenance', authority_verified: true)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(
            event_type:     'lifecycle_transition',
            principal_id:   'manager-1',
            principal_type: 'human',
            action:         'transition',
            resource:       'worker-42',
            status:         'success'
          )
        )
      end

      it 'includes from_state, to_state, and reason in detail' do
        described_class.transition!(worker, to_state: 'paused', by: 'manager-1',
                                            reason: 'maintenance', authority_verified: true)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(
            detail: { from_state: 'active', to_state: 'paused', reason: 'maintenance' }
          )
        )
      end

      it 'still returns the worker when audit publishing raises' do
        allow(Legion::Audit).to receive(:record).and_raise(StandardError, 'audit down')
        result = described_class.transition!(worker, to_state: 'paused', by: 'mgr',
                                                     authority_verified: true)
        expect(result).to eq(worker)
      end
    end

    it 'does not call Legion::Audit.record when not defined' do
      hide_const('Legion::Audit')
      expect do
        described_class.transition!(worker, to_state: 'paused', by: 'mgr', authority_verified: true)
      end.not_to raise_error
    end
  end
end
