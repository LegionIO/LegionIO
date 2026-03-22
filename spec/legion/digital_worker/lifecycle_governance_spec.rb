# frozen_string_literal: true

require 'spec_helper'
require 'legion/digital_worker/lifecycle'

RSpec.describe Legion::DigitalWorker::Lifecycle do
  let(:worker) do
    double('Worker',
           lifecycle_state: 'active',
           worker_id: 'w1',
           retired_at: nil,
           retired_by: nil,
           retired_reason: nil,
           update: true)
  end

  before do
    hide_const('Legion::Events') if defined?(Legion::Events)
    hide_const('Legion::Audit') if defined?(Legion::Audit)
  end

  describe '.transition! with lex-governance loaded' do
    let(:governance_runner) { Module.new }

    before do
      stub_const('Legion::Extensions::Governance::Runners::Governance', governance_runner)
    end

    it 'calls review_transition and proceeds when allowed' do
      allow(governance_runner).to receive(:review_transition).and_return({ allowed: true, checks: [] })
      expect(worker).to receive(:update)
      described_class.transition!(worker, to_state: 'paused', by: 'owner1')
    end

    it 'raises GovernanceBlocked when review returns not allowed' do
      allow(governance_runner).to receive(:review_transition).and_return(
        { allowed: false, reasons: [:council_approval_required] }
      )
      expect do
        described_class.transition!(worker, to_state: 'terminated', by: 'user1')
      end.to raise_error(Legion::DigitalWorker::Lifecycle::GovernanceBlocked, /council_approval_required/)
    end

    it 'passes worker_id, from_state, to_state, and principal_id' do
      expect(governance_runner).to receive(:review_transition).with(
        hash_including(worker_id: 'w1', from_state: 'active', to_state: 'paused', principal_id: 'owner1')
      ).and_return({ allowed: true, checks: [] })
      allow(worker).to receive(:update)
      described_class.transition!(worker, to_state: 'paused', by: 'owner1')
    end
  end

  describe '.transition! without lex-governance loaded' do
    before do
      hide_const('Legion::Extensions::Governance') if defined?(Legion::Extensions::Governance)
    end

    it 'falls back to legacy governance check' do
      expect do
        described_class.transition!(worker, to_state: 'terminated', by: 'user1')
      end.to raise_error(Legion::DigitalWorker::Lifecycle::GovernanceRequired)
    end

    it 'proceeds with governance_override and authority_verified flags' do
      expect(worker).to receive(:update)
      described_class.transition!(worker, to_state: 'terminated', by: 'user1',
                                         governance_override: true, authority_verified: true)
    end
  end
end
