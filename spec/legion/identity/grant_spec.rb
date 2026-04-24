# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/grant'

RSpec.describe Legion::Identity::Grant do
  describe 'granted access' do
    subject(:grant) do
      described_class.new(
        grant_id: 'g-123', token: 'secret_token', provider: :entra,
        qualifier: :default, purpose: 'graph_api', result: :granted,
        expires_at: Time.now + 3600
      )
    end

    it { is_expected.to be_granted }
    it { is_expected.not_to be_denied }

    it 'exposes token' do
      expect(grant.token).to eq('secret_token')
    end

    it 'exposes provider' do
      expect(grant.provider).to eq(:entra)
    end

    it 'exposes grant_id' do
      expect(grant.grant_id).to eq('g-123')
    end

    it 'exposes qualifier' do
      expect(grant.qualifier).to eq(:default)
    end

    it 'exposes purpose' do
      expect(grant.purpose).to eq('graph_api')
    end

    it 'is frozen' do
      expect(grant).to be_frozen
    end
  end

  describe 'denied access' do
    subject(:grant) do
      described_class.new(
        grant_id: 'g-456', token: nil, provider: :entra,
        qualifier: :app, purpose: 'admin_op', result: :denied,
        reason: 'rbac:insufficient_role'
      )
    end

    it { is_expected.to be_denied }
    it { is_expected.not_to be_granted }

    it 'exposes reason' do
      expect(grant.reason).to eq('rbac:insufficient_role')
    end

    it 'has nil token' do
      expect(grant.token).to be_nil
    end

    it 'has nil expires_at' do
      expect(grant.expires_at).to be_nil
    end
  end

  describe 'defaults' do
    subject(:grant) do
      described_class.new(grant_id: 'g-789', token: 'tok', provider: :test, result: :granted)
    end

    it 'defaults qualifier to :default' do
      expect(grant.qualifier).to eq(:default)
    end

    it 'defaults purpose to nil' do
      expect(grant.purpose).to be_nil
    end

    it 'defaults reason to nil' do
      expect(grant.reason).to be_nil
    end
  end
end
