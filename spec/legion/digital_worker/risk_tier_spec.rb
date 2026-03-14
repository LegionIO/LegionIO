# frozen_string_literal: true

require 'spec_helper'
require 'legion/digital_worker/registry'
require 'legion/digital_worker/risk_tier'

RSpec.describe Legion::DigitalWorker::RiskTier do
  describe 'TIERS' do
    it 'contains the four AIRB risk tiers in ascending order' do
      expect(described_class::TIERS).to eq(%w[low medium high critical])
    end

    it 'is frozen' do
      expect(described_class::TIERS).to be_frozen
    end
  end

  describe 'CONSTRAINTS' do
    it 'is frozen' do
      expect(described_class::CONSTRAINTS).to be_frozen
    end

    it 'covers all tiers' do
      described_class::TIERS.each do |tier|
        expect(described_class::CONSTRAINTS).to have_key(tier)
      end
    end
  end

  describe '.valid?' do
    it 'returns true for known tiers' do
      %w[low medium high critical].each do |tier|
        expect(described_class.valid?(tier)).to be(true)
      end
    end

    it 'returns false for unknown tiers' do
      expect(described_class.valid?('extreme')).to be(false)
      expect(described_class.valid?('')).to be(false)
      expect(described_class.valid?(nil)).to be(false)
    end
  end

  describe '.constraints_for' do
    it 'returns the constraint hash for a valid tier' do
      result = described_class.constraints_for('low')
      expect(result).to be_a(Hash)
      expect(result).to have_key(:min_consent)
      expect(result).to have_key(:governance_gate)
      expect(result).to have_key(:council_required)
    end

    it 'raises ArgumentError for an unknown tier' do
      expect { described_class.constraints_for('extreme') }.to raise_error(ArgumentError, /unknown risk tier: extreme/)
    end

    it 'includes valid tier list in the error message' do
      expect { described_class.constraints_for('bogus') }.to raise_error(ArgumentError, /low, medium, high, critical/)
    end
  end

  describe '.min_consent' do
    it 'returns notify for low tier' do
      expect(described_class.min_consent('low')).to eq('notify')
    end

    it 'returns consult for medium tier' do
      expect(described_class.min_consent('medium')).to eq('consult')
    end

    it 'returns consult for high tier' do
      expect(described_class.min_consent('high')).to eq('consult')
    end

    it 'returns supervised for critical tier' do
      expect(described_class.min_consent('critical')).to eq('supervised')
    end
  end

  describe '.governance_required?' do
    it 'returns false for low tier' do
      expect(described_class.governance_required?('low')).to be(false)
    end

    it 'returns false for medium tier' do
      expect(described_class.governance_required?('medium')).to be(false)
    end

    it 'returns true for high tier' do
      expect(described_class.governance_required?('high')).to be(true)
    end

    it 'returns true for critical tier' do
      expect(described_class.governance_required?('critical')).to be(true)
    end
  end

  describe '.council_required?' do
    it 'returns false for low tier' do
      expect(described_class.council_required?('low')).to be(false)
    end

    it 'returns false for medium tier' do
      expect(described_class.council_required?('medium')).to be(false)
    end

    it 'returns true for high tier' do
      expect(described_class.council_required?('high')).to be(true)
    end

    it 'returns true for critical tier' do
      expect(described_class.council_required?('critical')).to be(true)
    end
  end

  describe '.assign!' do
    let(:worker) do
      double('worker',
             worker_id:    'abc-123',
             risk_tier:    nil,
             consent_tier: 'supervised')
    end

    before do
      allow(worker).to receive(:update)
      allow(Legion::Logging).to receive(:info)
      allow(Legion::Logging).to receive(:warn)
    end

    it 'raises ArgumentError for an invalid tier' do
      expect { described_class.assign!(worker, tier: 'extreme', by: 'admin') }
        .to raise_error(ArgumentError, /invalid tier: extreme/)
    end

    it 'calls update on the worker with the new tier' do
      expect(worker).to receive(:update).with(hash_including(risk_tier: 'high'))
      described_class.assign!(worker, tier: 'high', by: 'admin')
    end

    it 'returns a hash with assigned: true' do
      result = described_class.assign!(worker, tier: 'medium', by: 'admin')
      expect(result[:assigned]).to be(true)
    end

    it 'includes event metadata in the returned hash' do
      result = described_class.assign!(worker, tier: 'low', by: 'tester', reason: 'review passed')
      expect(result[:worker_id]).to eq('abc-123')
      expect(result[:to_tier]).to eq('low')
      expect(result[:by]).to eq('tester')
      expect(result[:reason]).to eq('review passed')
    end

    it 'logs a warning when tier is lowered' do
      allow(worker).to receive(:risk_tier).and_return('critical')
      expect(Legion::Logging).to receive(:warn).with(/lowering risk from critical to high/)
      described_class.assign!(worker, tier: 'high', by: 'admin')
    end

    it 'does not warn when tier is the same or raised' do
      allow(worker).to receive(:risk_tier).and_return('low')
      expect(Legion::Logging).not_to receive(:warn)
      described_class.assign!(worker, tier: 'high', by: 'admin')
    end

    it 'emits a worker.risk_tier_changed event when Legion::Events is defined' do
      allow(Legion::Events).to receive(:emit)
      described_class.assign!(worker, tier: 'medium', by: 'admin')
      expect(Legion::Events).to have_received(:emit).with('worker.risk_tier_changed', hash_including(worker_id: 'abc-123'))
    end
  end

  describe '.consent_compliant?' do
    # CONSENT_HIERARCHY = %w[supervised consult notify autonomous]
    # Index 0=supervised, 1=consult, 2=notify, 3=autonomous
    # Compliant when hierarchy.index(worker.consent_tier) >= hierarchy.index(min_consent)
    let(:worker) { double('worker', worker_id: 'abc-123') }

    it 'returns true when worker has no risk tier' do
      allow(worker).to receive(:risk_tier).and_return(nil)
      expect(described_class.consent_compliant?(worker)).to be(true)
    end

    it 'returns true when consent tier exactly meets the minimum' do
      # low requires 'notify' (index 2); worker at 'notify' (index 2) — compliant
      allow(worker).to receive(:risk_tier).and_return('low')
      allow(worker).to receive(:consent_tier).and_return('notify')
      expect(described_class.consent_compliant?(worker)).to be(true)
    end

    it 'returns true when consent tier exceeds the minimum' do
      # low requires 'notify' (index 2); 'autonomous' is index 3 — compliant
      allow(worker).to receive(:risk_tier).and_return('low')
      allow(worker).to receive(:consent_tier).and_return('autonomous')
      expect(described_class.consent_compliant?(worker)).to be(true)
    end

    it 'returns false when consent tier is below the minimum' do
      # low requires 'notify' (index 2); 'supervised' is index 0 — non-compliant
      allow(worker).to receive(:risk_tier).and_return('low')
      allow(worker).to receive(:consent_tier).and_return('supervised')
      expect(described_class.consent_compliant?(worker)).to be(false)
    end

    it 'returns true for critical tier with any consent tier' do
      # critical requires 'supervised' (index 0); every tier has index >= 0
      allow(worker).to receive(:risk_tier).and_return('critical')
      allow(worker).to receive(:consent_tier).and_return('supervised')
      expect(described_class.consent_compliant?(worker)).to be(true)
    end

    it 'returns false for medium tier with supervised consent' do
      # medium requires 'consult' (index 1); 'supervised' is index 0 — non-compliant
      allow(worker).to receive(:risk_tier).and_return('medium')
      allow(worker).to receive(:consent_tier).and_return('supervised')
      expect(described_class.consent_compliant?(worker)).to be(false)
    end
  end
end
