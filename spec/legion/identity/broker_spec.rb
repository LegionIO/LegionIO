# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/lease'
require 'legion/identity/lease_renewer'
require 'legion/identity/process'
require 'legion/identity/broker'

RSpec.describe Legion::Identity::Broker do
  def make_lease(valid: true, token: 'tok.abc123')
    double(
      'Lease',
      valid?: valid,
      token:  token,
      to_h:   { token: token, valid: valid }
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
    it 'returns a hash of provider -> lease.to_h' do
      lease = make_lease(token: 'mytok')
      renewer = make_renewer(lease: lease)
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)

      described_class.register_provider(:vault, provider: double, lease: make_lease)

      result = described_class.leases
      expect(result[:vault]).to eq({ token: 'mytok', valid: true })
    end

    it 'returns nil for providers with no current lease' do
      renewer = make_renewer(lease: nil)
      allow(Legion::Identity::LeaseRenewer).to receive(:new).and_return(renewer)
      described_class.register_provider(:vault, provider: double, lease: make_lease)

      expect(described_class.leases[:vault]).to be_nil
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
end
