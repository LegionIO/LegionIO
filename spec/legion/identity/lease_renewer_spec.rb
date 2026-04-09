# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/lease'
require 'legion/identity/lease_renewer'

RSpec.describe Legion::Identity::LeaseRenewer do
  let(:provider_name) { :vault }
  let(:now)           { Time.now }

  def make_lease(ttl_seconds: 10, offset: 0)
    issued     = now - offset
    expires_at = issued + ttl_seconds
    Legion::Identity::Lease.new(
      provider:   :vault,
      credential: 'tok.abc123',
      issued_at:  issued,
      expires_at: expires_at
    )
  end

  let(:initial_lease) { make_lease(ttl_seconds: 10) }

  let(:provider) do
    instance_double('Provider').tap do |p|
      allow(p).to receive(:provide_token).and_return(make_lease(ttl_seconds: 10))
    end
  end

  subject(:renewer) do
    described_class.new(provider_name: provider_name, provider: provider, lease: initial_lease)
  end

  after do
    renewer.stop! if renewer.alive?
  end

  describe '#initialize' do
    it 'starts the background thread immediately' do
      expect(renewer.alive?).to be(true)
    end

    it 'names the thread after the provider' do
      renewer # trigger subject creation so the thread exists
      thread_name = Thread.list.find { |t| t.name == "lease-renewer-#{provider_name}" }&.name
      expect(thread_name).to eq("lease-renewer-#{provider_name}")
    end
  end

  describe '#provider_name' do
    it 'returns the provider name' do
      expect(renewer.provider_name).to eq(provider_name)
    end
  end

  describe '#provider' do
    it 'returns the provider object' do
      expect(renewer.provider).to equal(provider)
    end

    it 'is readable (not private)' do
      expect { renewer.provider }.not_to raise_error
    end
  end

  describe '#current_lease' do
    it 'returns the initial lease without blocking' do
      expect(renewer.current_lease).to equal(initial_lease)
    end

    it 'never blocks (returns immediately)' do
      t0 = Time.now
      renewer.current_lease
      expect(Time.now - t0).to be < 0.05
    end
  end

  describe '#alive?' do
    it 'returns true while the thread is running' do
      expect(renewer.alive?).to be(true)
    end

    it 'returns false after stop!' do
      renewer.stop!
      expect(renewer.alive?).to be(false)
    end
  end

  describe '#stop!' do
    it 'cooperatively shuts down the thread' do
      expect(renewer.alive?).to be(true)
      renewer.stop!
      expect(renewer.alive?).to be(false)
    end

    it 'returns within bounded time (< 6 seconds)' do
      t0 = Time.now
      renewer.stop!
      expect(Time.now - t0).to be < 6
    end

    it 'is safe to call multiple times' do
      renewer.stop!
      expect { renewer.stop! }.not_to raise_error
    end
  end

  describe 'lease renewal' do
    it 'renews the lease when the current lease becomes stale' do
      # Build a lease that is already past the 50% mark so the first sleep is tiny
      stale_lease  = make_lease(ttl_seconds: 3, offset: 2) # 67% elapsed
      new_lease    = make_lease(ttl_seconds: 10)

      allow(provider).to receive(:provide_token).and_return(new_lease)

      r = described_class.new(provider_name: :vault, provider: provider, lease: stale_lease)

      # Give the background thread up to 3 seconds to perform the renewal
      deadline = Time.now + 3
      sleep 0.1 until r.current_lease.equal?(new_lease) || Time.now > deadline

      expect(r.current_lease).to equal(new_lease)
    ensure
      r&.stop!
    end

    it 'does not replace the lease when provider returns nil' do
      stale_lease = make_lease(ttl_seconds: 2, offset: 1) # 50% elapsed
      allow(provider).to receive(:provide_token).and_return(nil)

      r = described_class.new(provider_name: :vault, provider: provider, lease: stale_lease)
      sleep 0.5
      expect(r.current_lease).to equal(stale_lease)
    ensure
      r&.stop!
    end

    it 'does not replace the lease when provider returns an invalid lease' do
      stale_lease   = make_lease(ttl_seconds: 2, offset: 1)
      invalid_lease = Legion::Identity::Lease.new(provider: :vault, credential: nil)
      allow(provider).to receive(:provide_token).and_return(invalid_lease)

      r = described_class.new(provider_name: :vault, provider: provider, lease: stale_lease)
      sleep 0.5
      expect(r.current_lease).to equal(stale_lease)
    ensure
      r&.stop!
    end
  end

  describe 'error handling' do
    it 'does not crash the thread when provider raises StandardError' do
      stale_lease = make_lease(ttl_seconds: 2, offset: 1)
      call_count  = 0
      good_lease  = make_lease(ttl_seconds: 10)

      allow(provider).to receive(:provide_token) do
        call_count += 1
        raise StandardError, 'temporary error' if call_count == 1

        good_lease
      end

      r = described_class.new(provider_name: :vault, provider: provider, lease: stale_lease)

      deadline = Time.now + 10
      sleep 0.1 until r.current_lease.equal?(good_lease) || Time.now > deadline

      expect(r.alive?).to be(true)
      expect(r.current_lease).to equal(good_lease)
    ensure
      r&.stop!
    end

    it 'logs renewal failures to $stderr when Legion::Logging is unavailable' do
      # Use a nearly-expired lease so compute_sleep returns MIN_SLEEP (1s) and renewal triggers quickly
      stale_lease = make_lease(ttl_seconds: 2, offset: 1.9)
      allow(provider).to receive(:provide_token).and_raise(StandardError, 'boom')

      hide_const('Legion::Logging') if defined?(Legion::Logging)

      expect($stderr).to receive(:puts).with(/LeaseRenewer.*vault.*boom/).at_least(:once)

      r = described_class.new(provider_name: :vault, provider: provider, lease: stale_lease)
      sleep 1.5
    ensure
      r&.stop!
    end
  end

  describe '#compute_sleep (private)' do
    subject(:renewer_bare) do
      described_class.new(provider_name: :vault, provider: provider, lease: initial_lease)
    end

    after { renewer_bare.stop! }

    it 'returns 50% of remaining TTL for a lease with expiry info' do
      # 10-second TTL, just issued — remaining is ~10s, half is ~5s
      lease  = make_lease(ttl_seconds: 10)
      result = renewer_bare.send(:compute_sleep, lease)
      expect(result).to be_between(4.5, 5.5)
    end

    it 'returns DEFAULT_SLEEP when lease is nil' do
      result = renewer_bare.send(:compute_sleep, nil)
      expect(result).to eq(described_class::DEFAULT_SLEEP)
    end

    it 'returns DEFAULT_SLEEP when expires_at is nil' do
      lease  = Legion::Identity::Lease.new(provider: :vault, credential: 'tok', expires_at: nil)
      result = renewer_bare.send(:compute_sleep, lease)
      expect(result).to eq(described_class::DEFAULT_SLEEP)
    end

    it 'returns DEFAULT_SLEEP when issued_at is nil' do
      lease = Legion::Identity::Lease.new(
        provider:   :vault,
        credential: 'tok',
        expires_at: Time.now + 100,
        issued_at:  nil
      )
      allow(lease).to receive(:issued_at).and_return(nil)
      result = renewer_bare.send(:compute_sleep, lease)
      expect(result).to eq(described_class::DEFAULT_SLEEP)
    end

    it 'returns MIN_SLEEP when remaining TTL is very small' do
      # Nearly expired: expires_at is 0.5s from now
      lease = Legion::Identity::Lease.new(
        provider:   :vault,
        credential: 'tok',
        issued_at:  Time.now - 99.5,
        expires_at: Time.now + 0.5
      )
      result = renewer_bare.send(:compute_sleep, lease)
      expect(result).to eq(described_class::MIN_SLEEP)
    end
  end
end
