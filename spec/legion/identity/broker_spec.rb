# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/lease'
require 'legion/identity/lease_renewer'
require 'legion/identity/process'
require 'legion/identity/broker'

RSpec.describe Legion::Identity::Broker do
  def make_lease(valid: true, token: 'tok.abc123', expires_at: Time.now + 3600, renewable: true)
    double(
      'Lease',
      valid?:     valid,
      token:      token,
      expires_at: expires_at,
      renewable:  renewable,
      to_h:       { token: token, valid: valid }
    )
  end

  def make_static_lease(token: 'static.key')
    double(
      'StaticLease',
      valid?:     true,
      token:      token,
      expires_at: nil,
      renewable:  false,
      to_h:       { token: token, valid: true }
    )
  end

  def make_renewer(lease: make_lease)
    double('LeaseRenewer', current_lease: lease, stop!: nil)
  end

  before(:each) { described_class.reset! }
  after(:each) { described_class.reset! }

  # ---------------------------------------------------------------------------
  # token_for
  # ---------------------------------------------------------------------------
  describe '.token_for' do
    context 'when provider is registered with a valid lease' do
      before do
        renewer = make_renewer(lease: make_lease(token: 'vault.token'))
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      end

      it 'returns the lease token' do
        expect(described_class.token_for(:vault)).to eq('vault.token')
      end
    end

    context 'when provider is not registered' do
      it 'returns nil' do
        expect(described_class.token_for(:unknown)).to be_nil
      end
    end

    context 'when the lease is invalid/expired' do
      before do
        renewer = make_renewer(lease: make_lease(valid: false, token: 'stale'))
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      end

      it 'returns nil' do
        expect(described_class.token_for(:vault)).to be_nil
      end
    end

    context 'when the renewer has a nil lease' do
      before do
        renewer = make_renewer(lease: nil)
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      end

      it 'returns nil' do
        expect(described_class.token_for(:vault)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # credentials_for
  # ---------------------------------------------------------------------------
  describe '.credentials_for' do
    context 'when provider is registered with a valid lease' do
      let(:lease) { make_lease(token: 'cred.token') }

      before do
        renewer = make_renewer(lease: lease)
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:kerberos, provider: double('p'), lease: make_lease)
      end

      it 'returns a hash with token' do
        result = described_class.credentials_for(:kerberos)
        expect(result[:token]).to eq('cred.token')
      end

      it 'returns a hash with provider' do
        result = described_class.credentials_for(:kerberos)
        expect(result[:provider]).to eq(:kerberos)
      end

      it 'returns a hash with service when provided' do
        result = described_class.credentials_for(:kerberos, service: 'HTTP/host.example.com')
        expect(result[:service]).to eq('HTTP/host.example.com')
      end

      it 'returns nil for service when not provided' do
        result = described_class.credentials_for(:kerberos)
        expect(result[:service]).to be_nil
      end

      it 'returns the lease object' do
        result = described_class.credentials_for(:kerberos)
        expect(result[:lease]).to equal(lease)
      end
    end

    context 'when provider is not registered' do
      it 'returns nil' do
        expect(described_class.credentials_for(:ghost)).to be_nil
      end
    end

    context 'when the lease is invalid' do
      before do
        renewer = make_renewer(lease: make_lease(valid: false))
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      end

      it 'returns nil' do
        expect(described_class.credentials_for(:vault)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # register_provider
  # ---------------------------------------------------------------------------
  describe '.register_provider' do
    it 'creates a LeaseRenewer for the provider' do
      renewer = make_renewer
      expect(Legion::Identity::LeaseRenewer).to receive(:new).with(
        provider_name: :vault,
        provider:      anything,
        lease:         anything
      ).and_return(renewer)

      described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      expect(described_class.providers).to include(:vault)
    end

    it 'stops the existing renewer before replacing it' do
      old_renewer = make_renewer
      new_renewer = make_renewer

      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(old_renewer, new_renewer)

      described_class.register_provider(:vault, provider: double('p'), lease: make_lease)

      expect(old_renewer).to receive(:stop!)
      described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
    end

    it 'accepts string provider names and converts to symbol' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)

      described_class.register_provider('ldap', provider: double('p'), lease: make_lease)
      expect(described_class.providers).to include(:ldap)
    end

    context 'with a static credential (expires_at: nil, renewable: false)' do
      it 'does NOT create a LeaseRenewer' do
        expect(Legion::Identity::LeaseRenewer).not_to receive(:new)
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease)
      end

      it 'includes the provider in providers list' do
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease)
        expect(described_class.providers).to include(:openai)
      end

      it 'stores the lease so token_for returns the token' do
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease(token: 'sk-abc'))
        expect(described_class.token_for(:openai)).to eq('sk-abc')
      end

      it 'stores the lease so lease_for returns the lease object' do
        lease = make_static_lease
        described_class.register_provider(:openai, provider: double('p'), lease: lease)
        expect(described_class.lease_for(:openai)).to equal(lease)
      end

      it 'returns nil from renewer_for' do
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease)
        expect(described_class.renewer_for(:openai)).to be_nil
      end

      it 'stops any existing renewer before switching to static' do
        renewer = make_renewer
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:openai, provider: double('p'), lease: make_lease)

        expect(renewer).to receive(:stop!)
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease)
      end

      it 'replaces a static lease when re-registered' do
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease(token: 'old'))
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease(token: 'new'))
        expect(described_class.token_for(:openai)).to eq('new')
      end
    end

    context 'switching from static to dynamic' do
      it 'removes the static lease and creates a LeaseRenewer' do
        described_class.register_provider(:vault, provider: double('p'), lease: make_static_lease)

        renewer = make_renewer
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)

        expect(described_class.renewer_for(:vault)).to equal(renewer)
        expect(described_class.lease_for(:vault)).to eq(renewer.current_lease)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # lease_for
  # ---------------------------------------------------------------------------
  describe '.lease_for' do
    context 'when provider has a dynamic renewer' do
      before do
        lease   = make_lease(token: 'dyn.tok')
        renewer = make_renewer(lease: lease)
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)
      end

      it 'returns the current lease from the renewer' do
        result = described_class.lease_for(:vault)
        expect(result.token).to eq('dyn.tok')
      end
    end

    context 'when provider has a static lease' do
      it 'returns the stored static lease' do
        lease = make_static_lease(token: 'api.key')
        described_class.register_provider(:openai, provider: double('p'), lease: lease)
        expect(described_class.lease_for(:openai)).to equal(lease)
      end
    end

    context 'when provider is not registered' do
      it 'returns nil' do
        expect(described_class.lease_for(:unknown)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # renewer_for
  # ---------------------------------------------------------------------------
  describe '.renewer_for' do
    context 'when provider has a dynamic renewer' do
      it 'returns the LeaseRenewer instance' do
        renewer = make_renewer
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:kerberos, provider: double('p'), lease: make_lease)

        expect(described_class.renewer_for(:kerberos)).to equal(renewer)
      end
    end

    context 'when provider is static' do
      it 'returns nil' do
        described_class.register_provider(:openai, provider: double('p'), lease: make_static_lease)
        expect(described_class.renewer_for(:openai)).to be_nil
      end
    end

    context 'when provider is not registered' do
      it 'returns nil' do
        expect(described_class.renewer_for(:ghost)).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # refresh_credential
  # ---------------------------------------------------------------------------
  describe '.refresh_credential' do
    context 'when provider is static and supports provide_token' do
      let(:new_lease) { make_static_lease(token: 'refreshed.key') }
      let(:provider)  { double('StaticProvider', provide_token: new_lease) }

      before do
        described_class.register_provider(:openai, provider: provider, lease: make_static_lease(token: 'old.key'))
      end

      it 'returns true' do
        expect(described_class.refresh_credential(:openai)).to be(true)
      end

      it 'updates the stored lease' do
        described_class.refresh_credential(:openai)
        expect(described_class.token_for(:openai)).to eq('refreshed.key')
      end
    end

    context 'when provider is dynamic (not static)' do
      it 'returns false' do
        renewer = make_renewer
        allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
        described_class.register_provider(:vault, provider: double('p'), lease: make_lease)

        expect(described_class.refresh_credential(:vault)).to be(false)
      end
    end

    context 'when provider is not registered' do
      it 'returns false' do
        expect(described_class.refresh_credential(:unknown)).to be(false)
      end
    end

    context 'when provider returns nil from provide_token' do
      it 'returns false and does not change the existing lease' do
        provider = double('BadProvider', provide_token: nil)
        described_class.register_provider(:openai, provider: provider, lease: make_static_lease(token: 'orig.key'))

        result = described_class.refresh_credential(:openai)
        expect(result).to be(false)
        expect(described_class.token_for(:openai)).to eq('orig.key')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # authenticated?
  # ---------------------------------------------------------------------------
  describe '.authenticated?' do
    it 'delegates to Identity::Process.resolved? when true' do
      allow(Legion::Identity::Process).to receive(:resolved?).and_return(true)
      expect(described_class.authenticated?).to be(true)
    end

    it 'delegates to Identity::Process.resolved? when false' do
      allow(Legion::Identity::Process).to receive(:resolved?).and_return(false)
      expect(described_class.authenticated?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # groups
  # ---------------------------------------------------------------------------
  describe '.groups' do
    before do
      allow(Legion::Identity::Process).to receive(:identity_hash).and_return({ groups: [] })
      allow(Legion::Identity::Process).to receive(:id).and_return('principal-1')
    end

    context 'when cache is warm and within TTL' do
      it 'returns cached groups without re-fetching' do
        allow(Legion::Identity::Process).to receive(:identity_hash)
          .and_return({ groups: %w[admin ops] })

        first_call = described_class.groups
        expect(Legion::Identity::Process).not_to receive(:identity_hash)
        second_call = described_class.groups

        expect(first_call).to eq(%w[admin ops])
        expect(second_call).to eq(%w[admin ops])
      end
    end

    context 'when cache is empty' do
      it 'fetches groups from Identity::Process when non-empty' do
        allow(Legion::Identity::Process).to receive(:identity_hash)
          .and_return({ groups: %w[dev qa] })

        expect(described_class.groups).to eq(%w[dev qa])
      end

      it 'returns empty array when Process groups are empty and DB unavailable' do
        allow(Legion::Identity::Process).to receive(:identity_hash)
          .and_return({ groups: [] })
        hide_const('Legion::Data') if defined?(Legion::Data)

        expect(described_class.groups).to eq([])
      end
    end

    context 'after TTL expires' do
      it 'fetches fresh groups' do
        allow(Legion::Identity::Process).to receive(:identity_hash)
          .and_return({ groups: ['initial'] }, { groups: ['refreshed'] })

        described_class.groups

        described_class.send(:instance_variable_get, :@groups_cache)
                       .set({ groups: ['initial'], fetched_at: Time.now - (described_class::GROUPS_CACHE_TTL + 1) })

        result = described_class.groups
        expect(result).to eq(['refreshed'])
      end
    end

    context 'single-flight: concurrent calls when fetch is in progress' do
      it 'does not trigger multiple concurrent fetches when stale cache exists' do
        # Prime the cache with a stale entry
        allow(Legion::Identity::Process).to receive(:identity_hash)
          .and_return({ groups: ['stale'] })
        described_class.groups

        # Now make the cache stale by backdating fetched_at
        described_class.instance_variable_get(:@groups_cache)
                       .set({ groups: ['stale'], fetched_at: Time.now - 120 })

        fetch_count = Concurrent::AtomicFixnum.new(0)
        allow(Legion::Identity::Process).to receive(:identity_hash) do
          fetch_count.increment
          sleep 0.05
          { groups: ['concurrent'] }
        end

        threads = Array.new(5) { Thread.new { described_class.groups } }
        results = threads.map(&:value)

        expect(fetch_count.value).to be <= 2
        results.each { |r| expect(r).to include('stale').or include('concurrent') }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # invalidate_groups_cache!
  # ---------------------------------------------------------------------------
  describe '.invalidate_groups_cache!' do
    it 'clears the groups cache so the next call re-fetches' do
      allow(Legion::Identity::Process).to receive(:identity_hash)
        .and_return({ groups: %w[cached] }, { groups: %w[fresh] })

      described_class.groups
      described_class.invalidate_groups_cache!

      expect(described_class.groups).to eq(%w[fresh])
    end
  end

  # ---------------------------------------------------------------------------
  # emails
  # ---------------------------------------------------------------------------
  describe '.emails' do
    it 'returns emails from Process identity_hash metadata' do
      allow(Legion::Identity::Process).to receive(:identity_hash)
        .and_return({ metadata: { emails: %w[a@example.com b@example.com] } })

      expect(described_class.emails).to eq(%w[a@example.com b@example.com])
    end

    it 'returns empty array when metadata has no emails' do
      allow(Legion::Identity::Process).to receive(:identity_hash).and_return({})
      expect(described_class.emails).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # providers
  # ---------------------------------------------------------------------------
  describe '.providers' do
    it 'returns empty array initially' do
      expect(described_class.providers).to eq([])
    end

    it 'returns registered provider names as symbols' do
      r1 = make_renewer
      r2 = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(r1, r2)

      described_class.register_provider(:vault, provider: double, lease: make_lease)
      described_class.register_provider(:kerberos, provider: double, lease: make_lease)

      expect(described_class.providers).to contain_exactly(:vault, :kerberos)
    end
  end

  # ---------------------------------------------------------------------------
  # leases
  # ---------------------------------------------------------------------------
  describe '.leases' do
    it 'returns a nested hash of provider -> qualifier -> lease.to_h' do
      lease = make_lease(token: 'mytok')
      renewer = make_renewer(lease: lease)
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)

      described_class.register_provider(:vault, provider: double, lease: make_lease)

      result = described_class.leases
      expect(result[:vault]).to be_a(Hash)
      expect(result[:vault][:default]).to eq({ token: 'mytok', valid: true })
    end

    it 'returns nil for qualifiers with no current lease' do
      renewer = make_renewer(lease: nil)
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:vault, provider: double, lease: make_lease)

      expect(described_class.leases[:vault][:default]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # shutdown
  # ---------------------------------------------------------------------------
  describe '.shutdown' do
    it 'calls stop! on all registered renewers' do
      r1 = make_renewer
      r2 = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(r1, r2)

      described_class.register_provider(:vault, provider: double, lease: make_lease)
      described_class.register_provider(:kerberos, provider: double, lease: make_lease)

      expect(r1).to receive(:stop!)
      expect(r2).to receive(:stop!)

      described_class.shutdown
    end

    it 'clears the providers list after shutdown' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:vault, provider: double, lease: make_lease)

      described_class.shutdown
      expect(described_class.providers).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # reset!
  # ---------------------------------------------------------------------------
  describe '.reset!' do
    it 'stops all renewers' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:vault, provider: double, lease: make_lease)

      expect(renewer).to receive(:stop!)
      described_class.reset!
    end

    it 'clears all providers' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:vault, provider: double, lease: make_lease)

      described_class.reset!
      expect(described_class.providers).to be_empty
    end

    it 'resets the groups cache so next groups call re-fetches' do
      allow(Legion::Identity::Process).to receive(:identity_hash)
        .and_return({ groups: %w[before] }, { groups: %w[after] })

      described_class.groups
      described_class.reset!

      expect(described_class.groups).to eq(%w[after])
    end

    it 'resets the in-progress flag to false' do
      described_class.reset!
      flag = described_class.instance_variable_get(:@groups_fetch_in_progress)
      expect(flag.true?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # backward-compatible registration (no qualifier)
  # ---------------------------------------------------------------------------
  describe 'backward-compatible registration (no qualifier)' do
    it 'registers and retrieves a token without specifying qualifier' do
      renewer = make_renewer(lease: make_lease(token: 'compat.tok'))
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:test, provider: double('p'), lease: make_lease)

      expect(described_class.token_for(:test)).to eq('compat.tok')
    end

    it 'includes the provider in the providers list' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:test, provider: double('p'), lease: make_lease)

      expect(described_class.providers).to include(:test)
    end

    it 'returns a lease from lease_for without qualifier' do
      lease = make_lease(token: 'compat.lease')
      renewer = make_renewer(lease: lease)
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:test, provider: double('p'), lease: make_lease)

      expect(described_class.lease_for(:test).token).to eq('compat.lease')
    end

    it 'returns credentials from credentials_for without qualifier' do
      renewer = make_renewer(lease: make_lease(token: 'compat.cred'))
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:test, provider: double('p'), lease: make_lease)

      result = described_class.credentials_for(:test)
      expect(result[:token]).to eq('compat.cred')
      expect(result[:provider]).to eq(:test)
    end

    it 'returns the renewer from renewer_for without qualifier' do
      renewer = make_renewer
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:test, provider: double('p'), lease: make_lease)

      expect(described_class.renewer_for(:test)).to equal(renewer)
    end

    it 'works with static credentials without qualifier' do
      described_class.register_provider(:api, provider: double('p'), lease: make_static_lease(token: 'sk-compat'))
      expect(described_class.token_for(:api)).to eq('sk-compat')
    end
  end

  # ---------------------------------------------------------------------------
  # multi-instance registration (with qualifier)
  # ---------------------------------------------------------------------------
  describe 'multi-instance registration (with qualifier)' do
    let(:delegated_lease) { make_static_lease(token: 'entra.delegated.tok') }
    let(:app_lease)       { make_static_lease(token: 'entra.app.tok') }

    before do
      described_class.register_provider(:entra,
                                        provider:  double('EntraProvider'),
                                        lease:     delegated_lease,
                                        qualifier: :delegated,
                                        default:   true)
      described_class.register_provider(:entra,
                                        provider:  double('EntraProvider'),
                                        lease:     app_lease,
                                        qualifier: :app)
    end

    it 'returns the default qualifier token when no qualifier specified' do
      expect(described_class.token_for(:entra)).to eq('entra.delegated.tok')
    end

    it 'returns the app qualifier token when qualifier: :app specified' do
      expect(described_class.token_for(:entra, qualifier: :app)).to eq('entra.app.tok')
    end

    it 'returns the delegated qualifier token when qualifier: :delegated specified' do
      expect(described_class.token_for(:entra, qualifier: :delegated)).to eq('entra.delegated.tok')
    end

    it 'lists both qualifiers via credentials_available' do
      expect(described_class.credentials_available(:entra)).to contain_exactly(:delegated, :app)
    end

    it 'includes :entra in providers exactly once' do
      expect(described_class.providers).to eq([:entra])
    end

    it 'returns nil for a non-existent qualifier' do
      expect(described_class.token_for(:entra, qualifier: :nonexistent)).to be_nil
    end

    it 'returns credentials_for with explicit qualifier' do
      result = described_class.credentials_for(:entra, qualifier: :app)
      expect(result[:token]).to eq('entra.app.tok')
      expect(result[:provider]).to eq(:entra)
    end

    it 'returns credentials_for using the default qualifier' do
      result = described_class.credentials_for(:entra)
      expect(result[:token]).to eq('entra.delegated.tok')
    end

    it 'returns an empty list for credentials_available on unregistered provider' do
      expect(described_class.credentials_available(:unknown)).to eq([])
    end

    it 'stops existing renewer for same tuple when re-registering' do
      renewer = make_renewer(lease: make_lease(token: 'dyn.tok'))
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:multi, provider: double('p'), lease: make_lease, qualifier: :slot_a)

      expect(renewer).to receive(:stop!)
      new_renewer = make_renewer(lease: make_lease(token: 'dyn.tok.new'))
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(new_renewer)
      described_class.register_provider(:multi, provider: double('p'), lease: make_lease, qualifier: :slot_a)
    end
  end

  # ---------------------------------------------------------------------------
  # context-based routing (for_context)
  # ---------------------------------------------------------------------------
  describe 'context-based routing (for_context)' do
    let(:legion_lease) { make_static_lease(token: 'gh.legion.tok') }
    let(:personal_lease) { make_static_lease(token: 'gh.personal.tok') }

    let(:routing_provider) do
      provider = double('GitHubProvider')
      allow(provider).to receive(:resolve_qualifier) do |ctx|
        case ctx[:org]
        when 'LegionIO' then :legion
        when 'Personal' then :personal
        end
      end
      provider
    end

    before do
      described_class.register_provider(:github,
                                        provider:  routing_provider,
                                        lease:     legion_lease,
                                        qualifier: :legion,
                                        default:   true)
      described_class.register_provider(:github,
                                        provider:  routing_provider,
                                        lease:     personal_lease,
                                        qualifier: :personal)
    end

    it 'routes to the correct qualifier based on for_context' do
      token = described_class.token_for(:github, for_context: { org: 'LegionIO' })
      expect(token).to eq('gh.legion.tok')
    end

    it 'routes to a different qualifier based on for_context' do
      token = described_class.token_for(:github, for_context: { org: 'Personal' })
      expect(token).to eq('gh.personal.tok')
    end

    it 'falls back to default when resolve_qualifier returns nil' do
      token = described_class.token_for(:github, for_context: { org: 'Unknown' })
      expect(token).to eq('gh.legion.tok')
    end

    it 'falls back to default when provider does not respond to resolve_qualifier' do
      plain_provider = double('PlainProvider')
      described_class.register_provider(:plain,
                                        provider:  plain_provider,
                                        lease:     make_static_lease(token: 'plain.default'),
                                        qualifier: :default)

      token = described_class.token_for(:plain, for_context: { org: 'Anything' })
      expect(token).to eq('plain.default')
    end

    it 'prefers explicit qualifier over for_context' do
      token = described_class.token_for(:github, qualifier: :personal, for_context: { org: 'LegionIO' })
      expect(token).to eq('gh.personal.tok')
    end
  end

  # ---------------------------------------------------------------------------
  # credentials_for with qualifier
  # ---------------------------------------------------------------------------
  describe 'credentials_for with qualifier' do
    before do
      described_class.register_provider(:gh,
                                        provider:  double('GHProvider'),
                                        lease:     make_static_lease(token: 'gh.default.tok'),
                                        qualifier: :default)
      described_class.register_provider(:gh,
                                        provider:  double('GHProvider'),
                                        lease:     make_static_lease(token: 'gh.esity.tok'),
                                        qualifier: :esity)
    end

    it 'returns default credentials when no qualifier given' do
      result = described_class.credentials_for(:gh)
      expect(result[:token]).to eq('gh.default.tok')
      expect(result[:provider]).to eq(:gh)
    end

    it 'returns specific credentials when qualifier given' do
      result = described_class.credentials_for(:gh, qualifier: :esity)
      expect(result[:token]).to eq('gh.esity.tok')
      expect(result[:provider]).to eq(:gh)
    end

    it 'returns nil when qualifier does not exist' do
      expect(described_class.credentials_for(:gh, qualifier: :nonexistent)).to be_nil
    end

    it 'passes service through to the result' do
      result = described_class.credentials_for(:gh, qualifier: :esity, service: 'api.github.com')
      expect(result[:service]).to eq('api.github.com')
    end
  end

  # ---------------------------------------------------------------------------
  # audit emission in token_for
  # ---------------------------------------------------------------------------
  describe 'audit emission in token_for' do
    it 'pushes an audit event to the queue on successful token_for' do
      described_class.register_provider(:aud, provider: double('p'), lease: make_static_lease(token: 'aud.tok'))
      described_class.token_for(:aud, purpose: 'api_call', context: { request_id: '123' })

      queue = described_class.instance_variable_get(:@audit_queue)
      expect(queue.size).to be >= 1
      event = queue.first
      expect(event[:provider]).to eq(:aud)
      expect(event[:qualifier]).to eq(:default)
      expect(event[:purpose]).to eq('api_call')
      expect(event[:context]).to eq({ request_id: '123' })
      expect(event[:granted]).to be(true)
      expect(event[:timestamp]).to be_a(Time)
    end

    it 'pushes an audit event with granted: false when token is nil' do
      described_class.token_for(:nonexistent, purpose: 'test')

      queue = described_class.instance_variable_get(:@audit_queue)
      event = queue.last
      expect(event[:granted]).to be(false)
    end

    it 'drops events when audit queue is full' do
      described_class.register_provider(:flood, provider: double('p'), lease: make_static_lease(token: 'f.tok'))

      # Fill the queue to capacity
      queue = described_class.instance_variable_get(:@audit_queue)
      Legion::Identity::Broker::AUDIT_QUEUE_MAX.times { queue.push({ filler: true }) }

      # This call should drop rather than push
      described_class.token_for(:flood)
      drops = described_class.instance_variable_get(:@audit_drops)
      expect(drops.value).to be >= 1
    end
  end
end
