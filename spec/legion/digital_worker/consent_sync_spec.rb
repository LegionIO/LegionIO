# frozen_string_literal: true

require 'spec_helper'
require 'legion/digital_worker/lifecycle'

RSpec.describe Legion::DigitalWorker::Lifecycle, 'consent sync' do
  let(:worker) do
    double('Worker',
           lifecycle_state: 'active',
           worker_id:       'w1',
           consent_tier:    'autonomous',
           retired_at:      nil,
           retired_by:      nil,
           retired_reason:  nil,
           owner_msid:      'owner@example.com',
           update:          true)
  end

  before do
    hide_const('Legion::Events') if defined?(Legion::Events)
    hide_const('Legion::Audit') if defined?(Legion::Audit)
    hide_const('Legion::Extensions::Governance') if defined?(Legion::Extensions::Governance)
    hide_const('Legion::Extensions::Extinction') if defined?(Legion::Extensions::Extinction)
    hide_const('Legion::Extensions::Consent') if defined?(Legion::Extensions::Consent)
  end

  describe 'consent tier update on transition' do
    it 'sets consent_tier to consult when paused' do
      expect(worker).to receive(:update).with(hash_including(consent_tier: 'consult'))
      described_class.transition!(worker, to_state: 'paused', by: 'owner1', authority_verified: true)
    end

    it 'sets consent_tier to inform when retired' do
      expect(worker).to receive(:update).with(hash_including(consent_tier: 'inform'))
      described_class.transition!(worker, to_state: 'retired', by: 'owner1', authority_verified: true)
    end

    it 'sets consent_tier to inform when terminated' do
      expect(worker).to receive(:update).with(hash_including(consent_tier: 'inform'))
      described_class.transition!(worker, to_state: 'terminated', by: 'admin', governance_override: true)
    end
  end

  describe 'lex-consent sync when available' do
    let(:consent_runner) { Module.new }

    before do
      stub_const('Legion::Extensions::Consent::Runners::Consent', consent_runner)
    end

    it 'calls update_tier on lex-consent runner' do
      allow(worker).to receive(:update)
      expect(consent_runner).to receive(:update_tier).with(worker_id: 'w1', tier: 'consult')
      described_class.transition!(worker, to_state: 'paused', by: 'owner1', authority_verified: true)
    end

    it 'does not raise when consent sync fails' do
      allow(worker).to receive(:update)
      allow(consent_runner).to receive(:update_tier).and_raise(StandardError, 'consent unavailable')
      expect do
        described_class.transition!(worker, to_state: 'paused', by: 'owner1', authority_verified: true)
      end.not_to raise_error
    end
  end

  describe 'without lex-consent loaded' do
    it 'transitions normally without consent sync' do
      allow(worker).to receive(:update)
      expect do
        described_class.transition!(worker, to_state: 'paused', by: 'owner1', authority_verified: true)
      end.not_to raise_error
    end
  end
end
