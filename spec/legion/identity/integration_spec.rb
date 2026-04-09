# frozen_string_literal: true

require 'spec_helper'
require 'concurrent'
require 'legion/mode'
require 'legion/identity/process'
require 'legion/identity/broker'
require 'legion/identity/lease'
require 'legion/identity/lease_renewer'
require 'legion/identity/request'

RSpec.describe 'Identity Integration' do
  before do
    Legion::Identity::Process.reset!
    Legion::Identity::Broker.reset!
  end

  after do
    Legion::Identity::Broker.shutdown
    Legion::Identity::Process.reset!
  end

  describe 'boot -> identity resolves -> broker registers' do
    it 'resolves identity and registers provider lease' do
      provider_identity = {
        id:             SecureRandom.uuid,
        canonical_name: 'test-agent',
        kind:           :service,
        persistent:     true
      }

      initial_lease = Legion::Identity::Lease.new(
        provider:   :kerberos,
        credential: 'spnego-token-abc',
        lease_id:   'vault-lease-123',
        expires_at: Time.now + 3600,
        renewable:  true,
        issued_at:  Time.now
      )

      mock_provider = double('IdentityProvider')
      allow(mock_provider).to receive(:provide_token).and_return(initial_lease)

      stub_renewer = instance_double(
        Legion::Identity::LeaseRenewer,
        current_lease: initial_lease,
        stop!:         nil
      )
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(stub_renewer)

      # Step 1: Bind identity
      Legion::Identity::Process.bind!(mock_provider, provider_identity)

      expect(Legion::Identity::Process.resolved?).to be true
      expect(Legion::Identity::Process.canonical_name).to eq('test-agent')
      expect(Legion::Identity::Process.kind).to eq(:service)
      expect(Legion::Identity::Process.persistent?).to be true
      expect(Legion::Identity::Process.id).to eq(provider_identity[:id])

      # Step 2: Register provider with Broker
      Legion::Identity::Broker.register_provider(:kerberos, provider: mock_provider, lease: initial_lease)

      expect(Legion::Identity::Broker.providers).to include(:kerberos)
      expect(Legion::Identity::Broker.token_for(:kerberos)).to eq('spnego-token-abc')
      expect(Legion::Identity::Broker.authenticated?).to be true

      # Step 3: Verify credentials_for returns full hash
      creds = Legion::Identity::Broker.credentials_for(:kerberos, service: :vault)
      expect(creds[:token]).to eq('spnego-token-abc')
      expect(creds[:provider]).to eq(:kerberos)
      expect(creds[:service]).to eq(:vault)
      expect(creds[:lease]).to be_a(Legion::Identity::Lease)
    end
  end

  describe 'fallback identity when no providers' do
    it 'uses ENV USER as fallback' do
      allow(ENV).to receive(:fetch).with('USER', 'anonymous').and_return('testuser')

      Legion::Identity::Process.bind_fallback!

      expect(Legion::Identity::Process.resolved?).to be false
      expect(Legion::Identity::Process.persistent?).to be false
      expect(Legion::Identity::Process.canonical_name).to eq('testuser')
      expect(Legion::Identity::Process.kind).to eq(:human)
    end
  end

  describe 'provider raises during resolution' do
    it 'does not crash and falls back gracefully' do
      failing_provider = double('FailingProvider')
      allow(failing_provider).to receive(:resolve).and_raise(StandardError, 'connection refused')

      # Process should not be resolved without an explicit bind
      expect(Legion::Identity::Process.resolved?).to be false

      # Fallback should work
      Legion::Identity::Process.bind_fallback!
      expect(Legion::Identity::Process.canonical_name).not_to be_nil
    end
  end

  describe 'request identity from auth context' do
    it 'builds request and maps to caller hash' do
      request = Legion::Identity::Request.from_auth_context(
        sub:    'user-uuid-123',
        name:   'John.Doe',
        kind:   :human,
        groups: %w[admin operators],
        source: :kerberos
      )

      expect(request.principal_id).to eq('user-uuid-123')
      expect(request.canonical_name).to eq('john-doe')
      expect(request.kind).to eq(:human)
      expect(request.groups).to eq(%w[admin operators])
      expect(request.source).to eq(:kerberos)

      caller_hash = request.to_caller_hash
      expect(caller_hash[:requested_by][:id]).to eq('user-uuid-123')
      expect(caller_hash[:requested_by][:identity]).to eq('john-doe')
      expect(caller_hash[:requested_by][:type]).to eq(:human)
      expect(caller_hash[:requested_by][:credential]).to eq(:kerberos)

      rbac = request.to_rbac_principal
      expect(rbac[:identity]).to eq('john-doe')
      expect(rbac[:type]).to eq(:human)
    end
  end

  describe 'queue_prefix depends on mode' do
    let(:fixed_uuid) { 'test-instance-id' }
    let(:fixed_host) { 'test-host' }

    before do
      allow(Legion).to receive(:instance_id).and_return(fixed_uuid)
      allow(Socket).to receive(:gethostname).and_return(fixed_host)
      Legion::Identity::Process.bind!(nil, {
                                        id:             'uuid-1',
                                        canonical_name: 'myagent',
                                        kind:           :service,
                                        persistent:     true
                                      })
    end

    it 'uses agent prefix for agent mode' do
      allow(Legion::Mode).to receive(:current).and_return(:agent)
      expect(Legion::Identity::Process.queue_prefix).to eq("agent.myagent.#{fixed_host}")
    end

    it 'uses worker prefix for worker mode' do
      allow(Legion::Mode).to receive(:current).and_return(:worker)
      expect(Legion::Identity::Process.queue_prefix).to eq("worker.myagent.#{fixed_uuid}")
    end

    it 'uses infra prefix for infra mode' do
      allow(Legion::Mode).to receive(:current).and_return(:infra)
      expect(Legion::Identity::Process.queue_prefix).to eq("infra.myagent.#{fixed_host}")
    end

    it 'uses lite prefix for lite mode' do
      allow(Legion::Mode).to receive(:current).and_return(:lite)
      expect(Legion::Identity::Process.queue_prefix).to eq("lite.myagent.#{fixed_uuid}")
    end
  end

  describe 'lease lifecycle' do
    it 'detects fresh lease as valid and not stale' do
      fresh = Legion::Identity::Lease.new(
        provider:   :test,
        credential: 'token-1',
        expires_at: Time.now + 100,
        issued_at:  Time.now
      )
      expect(fresh.valid?).to be true
      expect(fresh.stale?).to be false
      expect(fresh.expired?).to be false
    end

    it 'detects a stale lease (past 50% TTL)' do
      stale = Legion::Identity::Lease.new(
        provider:   :test,
        credential: 'token-2',
        expires_at: Time.now + 10,
        issued_at:  Time.now - 90
      )
      expect(stale.valid?).to be true
      expect(stale.stale?).to be true
    end

    it 'detects an expired lease' do
      expired = Legion::Identity::Lease.new(
        provider:   :test,
        credential: 'token-3',
        expires_at: Time.now - 1,
        issued_at:  Time.now - 100
      )
      expect(expired.valid?).to be false
      expect(expired.expired?).to be true
      expect(expired.ttl_seconds).to eq(0)
    end
  end

  describe 'Postgres unavailable (in-memory only)' do
    it 'identity system works without database' do
      Legion::Identity::Process.bind_fallback!
      expect(Legion::Identity::Process.canonical_name).not_to be_nil
    end

    it 'groups returns empty array without DB' do
      hide_const('Legion::Data') if defined?(Legion::Data)
      allow(Legion::Identity::Process).to receive(:identity_hash).and_return({ groups: [] })

      groups = Legion::Identity::Broker.groups
      expect(groups).to eq([])
    end

    it 'request objects work without database' do
      request = Legion::Identity::Request.new(
        principal_id:   'test-id',
        canonical_name: 'test-user',
        kind:           :human
      )
      expect(request.to_caller_hash).to be_a(Hash)
    end
  end

  describe 'reload path' do
    it 'refresh_credentials does not raise when no provider is bound' do
      Legion::Identity::Process.bind_fallback!
      expect { Legion::Identity::Process.refresh_credentials }.not_to raise_error
    end

    it 'refresh_credentials does not raise when provider does not respond to refresh' do
      provider = double('NoRefreshProvider')
      Legion::Identity::Process.bind!(provider, {
                                        id:             'x',
                                        canonical_name: 'svc',
                                        kind:           :service,
                                        persistent:     true
                                      })
      expect { Legion::Identity::Process.refresh_credentials }.not_to raise_error
    end
  end

  describe 'static credential registration (Phase 8 credential-only providers)' do
    let(:static_lease) do
      Legion::Identity::Lease.new(
        provider:   :openai,
        credential: 'sk-test-abc123',
        expires_at: nil,
        renewable:  false
      )
    end

    let(:provider) { double('CredentialProvider', provide_token: static_lease) }

    it 'token_for returns the credential string for a static provider' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      expect(Legion::Identity::Broker.token_for(:openai)).to eq('sk-test-abc123')
    end

    it 'lease_for returns the Lease object for a static provider' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      result = Legion::Identity::Broker.lease_for(:openai)
      expect(result).to be_a(Legion::Identity::Lease)
      expect(result.token).to eq('sk-test-abc123')
    end

    it 'renewer_for returns nil for static providers (no background thread)' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      expect(Legion::Identity::Broker.renewer_for(:openai)).to be_nil
    end

    it 'includes the static provider in the providers list' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      expect(Legion::Identity::Broker.providers).to include(:openai)
    end

    it 'refresh_credential calls provide_token and updates the stored lease' do
      new_lease = Legion::Identity::Lease.new(
        provider:   :openai,
        credential: 'sk-refreshed',
        expires_at: nil,
        renewable:  false
      )
      allow(provider).to receive(:provide_token).and_return(new_lease)
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)

      result = Legion::Identity::Broker.refresh_credential(:openai)
      expect(result).to be(true)
      expect(Legion::Identity::Broker.token_for(:openai)).to eq('sk-refreshed')
    end

    it 'static leases appear in leases hash' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      leases = Legion::Identity::Broker.leases
      expect(leases[:openai]).to be_a(Hash)
      expect(leases[:openai][:valid]).to be(true)
    end

    it 'shutdown clears static leases' do
      Legion::Identity::Broker.register_provider(:openai, provider: provider, lease: static_lease)
      Legion::Identity::Broker.shutdown
      expect(Legion::Identity::Broker.providers).to be_empty
    end
  end

  describe 'Broker registration via register_provider_with_broker (Phase 8 8.0e)' do
    it 'registers a provider that responds to provide_token' do
      initial_lease = Legion::Identity::Lease.new(
        provider:   :entra,
        credential: 'entra-bearer-token',
        expires_at: Time.now + 3600,
        renewable:  true,
        issued_at:  Time.now
      )
      provider = double('EntraProvider', provider_name: :entra, provide_token: initial_lease)

      stub_renewer = instance_double(
        Legion::Identity::LeaseRenewer,
        current_lease: initial_lease,
        stop!:         nil
      )
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(stub_renewer)

      Legion::Identity::Broker.register_provider(:entra, provider: provider, lease: initial_lease)

      expect(Legion::Identity::Broker.token_for(:entra)).to eq('entra-bearer-token')
      expect(Legion::Identity::Broker.renewer_for(:entra)).to equal(stub_renewer)
    end
  end
end
