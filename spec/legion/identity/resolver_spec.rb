# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity'
require 'legion/identity/resolver'
require 'legion/identity/process'
require 'legion/identity/trust'

RSpec.describe Legion::Identity::Resolver do # rubocop:disable Metrics/BlockLength
  before { described_class.reset_all! }
  after  { described_class.reset_all! }

  let(:kerberos_provider) do
    Module.new do
      extend self
      def provider_name  = :kerberos
      def provider_type  = :auth
      def priority       = 100
      def trust_weight   = 30
      def trust_level    = :verified
      def capabilities   = [:authenticate]
      def resolve
        { canonical_name: 'miverso2', kind: :human, source: :kerberos,
          provider_identity: 'miverso2@MS.DS.UHC.COM' }
      end
      def normalize(val) = val.to_s.split('@').first.downcase.gsub(/[^a-z0-9_-]/, '')
    end
  end

  let(:low_priority_auth) do
    Module.new do
      extend self
      def provider_name  = :entra
      def provider_type  = :auth
      def priority       = 50
      def trust_weight   = 50
      def trust_level    = :authenticated
      def capabilities   = [:authenticate]
      def resolve
        { canonical_name: 'miverso2-entra', kind: :human, source: :entra,
          provider_identity: 'eb282cc7-uuid' }
      end
      def normalize(val) = val.to_s.downcase
    end
  end

  let(:system_provider) do
    Module.new do
      extend self
      def provider_name  = :system
      def provider_type  = :fallback
      def priority       = 0
      def trust_weight   = 200
      def trust_level    = :unverified
      def capabilities   = [:profile]
      def resolve
        { canonical_name: 'testuser', kind: :human, source: :system,
          provider_identity: 'testuser' }
      end
      def normalize(val) = val.to_s.downcase.gsub(/[^a-z0-9_-]/, '')
    end
  end

  let(:profile_provider) do
    Module.new do
      extend self
      def provider_name  = :ldap
      def provider_type  = :profile
      def priority       = 0
      def trust_weight   = 10
      def trust_level    = :verified
      def capabilities   = %i[profile groups]
      def resolve(canonical_name:)
        { groups: ['devs'], profile: { department: 'Engineering' } }
      end
      def normalize(val) = val.to_s.downcase
    end
  end

  let(:timeout_provider) do
    Module.new do
      extend self
      def provider_name  = :slow_provider
      def provider_type  = :auth
      def priority       = 200
      def trust_weight   = 10
      def trust_level    = :verified
      def capabilities   = [:authenticate]
      def resolve
        sleep 10
        { canonical_name: 'slow-user', kind: :human, source: :slow_provider,
          provider_identity: 'slow@example.com' }
      end
      def normalize(val) = val.to_s.downcase
    end
  end

  let(:failing_provider) do
    Module.new do
      extend self
      def provider_name  = :broken
      def provider_type  = :auth
      def priority       = 150
      def trust_weight   = 20
      def trust_level    = :verified
      def capabilities   = [:authenticate]
      def resolve
        raise StandardError, 'connection refused'
      end
      def normalize(val) = val.to_s.downcase
    end
  end

  let(:nil_provider) do
    Module.new do
      extend self
      def provider_name  = :empty
      def provider_type  = :auth
      def priority       = 80
      def trust_weight   = 40
      def trust_level    = :authenticated
      def capabilities   = [:authenticate]
      def resolve        = nil
      def normalize(val) = val.to_s.downcase
    end
  end

  describe '.register' do
    it 'adds a provider' do
      described_class.register(kerberos_provider)
      expect(described_class.providers.size).to eq(1)
    end

    it 'ignores duplicates by provider_name' do
      described_class.register(kerberos_provider)
      described_class.register(kerberos_provider)
      expect(described_class.providers.size).to eq(1)
    end

    it 'accepts providers with different names' do
      described_class.register(kerberos_provider)
      described_class.register(system_provider)
      expect(described_class.providers.size).to eq(2)
    end
  end

  describe '.resolve!' do
    before do
      Legion::Identity::Process.reset!
    end

    after do
      Legion::Identity::Process.reset!
    end

    it 'sets resolved? to true after successful resolution' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.resolved?).to be(true)
    end

    it 'picks the highest-priority auth provider for canonical_name' do
      described_class.register(low_priority_auth)
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:canonical_name]).to eq('miverso2')
    end

    it 'sets trust from the winning provider trust_level method' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:trust]).to eq(:verified)
    end

    it 'records aliases as arrays per provider' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:aliases][:kerberos]).to eq(['miverso2@MS.DS.UHC.COM'])
    end

    it 'tracks all provider results in the composite' do
      described_class.register(kerberos_provider)
      described_class.register(low_priority_auth)
      described_class.resolve!
      providers_map = described_class.composite[:providers]
      expect(providers_map).to have_key(:kerberos)
      expect(providers_map).to have_key(:entra)
      expect(providers_map[:kerberos][:status]).to eq(:resolved)
      expect(providers_map[:entra][:status]).to eq(:resolved)
    end

    it 'binds Identity::Process' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(Legion::Identity::Process.resolved?).to be(true)
      expect(Legion::Identity::Process.canonical_name).to eq('miverso2')
    end

    it 'returns the composite hash' do
      described_class.register(kerberos_provider)
      result = described_class.resolve!
      expect(result).to be_a(Hash)
      expect(result[:canonical_name]).to eq('miverso2')
    end

    it 'returns nil when no providers are registered' do
      result = described_class.resolve!
      expect(result).to be_nil
      expect(described_class.resolved?).to be(false)
    end

    it 'sets persistent to true' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:persistent]).to be(true)
    end

    it 'sets source to the winning provider name' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:source]).to eq(:kerberos)
    end

    it 'sets kind from winning result' do
      described_class.register(kerberos_provider)
      described_class.resolve!
      expect(described_class.composite[:kind]).to eq(:human)
    end

    context 'with profile providers' do
      it 'merges groups from profile providers' do
        described_class.register(kerberos_provider)
        described_class.register(profile_provider)
        described_class.resolve!
        expect(described_class.composite[:groups]).to include('devs')
      end

      it 'merges profile data from profile providers' do
        described_class.register(kerberos_provider)
        described_class.register(profile_provider)
        described_class.resolve!
        expect(described_class.composite[:profile][:department]).to eq('Engineering')
      end

      it 'includes profile provider in the providers map' do
        described_class.register(kerberos_provider)
        described_class.register(profile_provider)
        described_class.resolve!
        expect(described_class.composite[:providers]).to have_key(:ldap)
        expect(described_class.composite[:providers][:ldap][:status]).to eq(:resolved)
      end
    end

    context 'with no auth providers but a fallback' do
      it 'falls back to the fallback provider' do
        described_class.register(system_provider)
        described_class.resolve!
        expect(described_class.resolved?).to be(true)
        expect(described_class.composite[:canonical_name]).to eq('testuser')
      end

      it 'uses fallback provider trust_level' do
        described_class.register(system_provider)
        described_class.resolve!
        expect(described_class.composite[:trust]).to eq(:unverified)
      end
    end

    context 'with a timeout provider' do
      it 'records :timeout status and falls through' do
        described_class.register(timeout_provider)
        described_class.register(kerberos_provider)
        result = described_class.resolve!(timeout: 1)
        expect(result[:canonical_name]).to eq('miverso2')
        expect(result[:providers][:slow_provider][:status]).to eq(:timeout)
      end
    end

    context 'with a failing provider' do
      it 'records :failed status' do
        described_class.register(failing_provider)
        described_class.register(kerberos_provider)
        described_class.resolve!
        expect(described_class.composite[:providers][:broken][:status]).to eq(:failed)
      end

      it 'still resolves via working providers' do
        described_class.register(failing_provider)
        described_class.register(kerberos_provider)
        described_class.resolve!
        expect(described_class.composite[:canonical_name]).to eq('miverso2')
      end
    end

    context 'with a nil-returning provider' do
      it 'records :no_identity status' do
        described_class.register(nil_provider)
        described_class.register(kerberos_provider)
        described_class.resolve!
        expect(described_class.composite[:providers][:empty][:status]).to eq(:no_identity)
      end
    end
  end

  describe '.reset!' do
    it 'preserves providers' do
      described_class.register(kerberos_provider)
      described_class.reset!
      expect(described_class.providers.size).to eq(1)
    end

    it 'clears composite' do
      described_class.register(kerberos_provider)
      Legion::Identity::Process.reset!
      described_class.resolve!
      described_class.reset!
      expect(described_class.composite).to be_nil
      expect(described_class.resolved?).to be(false)
      Legion::Identity::Process.reset!
    end

    it 'regenerates session_id' do
      old_session = described_class.session_id
      described_class.reset!
      expect(described_class.session_id).not_to eq(old_session)
    end
  end

  describe '.reset_all!' do
    it 'clears everything including providers' do
      described_class.register(kerberos_provider)
      described_class.reset_all!
      expect(described_class.providers).to be_empty
      expect(described_class.composite).to be_nil
      expect(described_class.resolved?).to be(false)
    end
  end

  describe 'pending registrations' do
    it 'drains pending registrations on resolve!' do
      Legion::Identity.pending_registrations << kerberos_provider
      Legion::Identity::Process.reset!
      described_class.resolve!
      expect(described_class.resolved?).to be(true)
      expect(described_class.composite[:canonical_name]).to eq('miverso2')
      expect(Legion::Identity.pending_registrations).to be_empty
      Legion::Identity::Process.reset!
    end
  end

  describe '.upgrade!' do
    before do
      Legion::Identity::Process.reset!
      described_class.register(system_provider)
      described_class.resolve!
    end

    after do
      Legion::Identity::Process.reset!
    end

    it 'upgrades trust level' do
      result = { canonical_name: 'testuser', kind: :human, source: :kerberos,
                 provider_identity: 'testuser@MS.DS.UHC.COM' }
      described_class.upgrade!(kerberos_provider, result)
      expect(described_class.composite[:trust]).to eq(:verified)
    end

    it 'adds new provider to providers map' do
      result = { canonical_name: 'testuser', kind: :human, source: :kerberos,
                 provider_identity: 'testuser@MS.DS.UHC.COM' }
      described_class.upgrade!(kerberos_provider, result)
      expect(described_class.composite[:providers]).to have_key(:kerberos)
      expect(described_class.composite[:providers][:kerberos][:status]).to eq(:resolved)
    end

    it 'adds alias from new provider' do
      result = { canonical_name: 'testuser', kind: :human, source: :kerberos,
                 provider_identity: 'testuser@MS.DS.UHC.COM' }
      described_class.upgrade!(kerberos_provider, result)
      expect(described_class.composite[:aliases][:kerberos]).to include('testuser@MS.DS.UHC.COM')
    end

    it 'can change canonical_name' do
      result = { canonical_name: 'miverso2', kind: :human, source: :kerberos,
                 provider_identity: 'miverso2@MS.DS.UHC.COM' }
      described_class.upgrade!(kerberos_provider, result)
      expect(described_class.composite[:canonical_name]).to eq('miverso2')
    end

    it 're-binds Identity::Process after upgrade' do
      result = { canonical_name: 'testuser', kind: :human, source: :kerberos,
                 provider_identity: 'testuser@MS.DS.UHC.COM' }
      described_class.upgrade!(kerberos_provider, result)
      expect(Legion::Identity::Process.trust).to eq(:verified)
    end
  end

  describe '.session_id' do
    it 'returns a UUID string' do
      expect(described_class.session_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end
  end

  describe 'tiebreaking' do
    it 'uses trust_weight for tiebreak when priorities are equal' do
      provider_a = Module.new do
        extend self
        def provider_name  = :provider_a
        def provider_type  = :auth
        def priority       = 100
        def trust_weight   = 50
        def trust_level    = :authenticated
        def capabilities   = [:authenticate]
        def resolve
          { canonical_name: 'user-a', kind: :human, source: :provider_a,
            provider_identity: 'user-a@example.com' }
        end
      end

      provider_b = Module.new do
        extend self
        def provider_name  = :provider_b
        def provider_type  = :auth
        def priority       = 100
        def trust_weight   = 10
        def trust_level    = :verified
        def capabilities   = [:authenticate]
        def resolve
          { canonical_name: 'user-b', kind: :human, source: :provider_b,
            provider_identity: 'user-b@example.com' }
        end
      end

      Legion::Identity::Process.reset!
      described_class.register(provider_a)
      described_class.register(provider_b)
      described_class.resolve!
      # Same priority (100), lower trust_weight wins tiebreak
      expect(described_class.composite[:canonical_name]).to eq('user-b')
      Legion::Identity::Process.reset!
    end
  end
end
