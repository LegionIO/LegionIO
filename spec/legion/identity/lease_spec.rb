# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/lease'

RSpec.describe Legion::Identity::Lease do
  let(:provider)   { :vault }
  let(:credential) { 's.abc123token' }
  let(:lease_id)   { 'auth/token/create/abc123' }
  let(:now)        { Time.now }
  let(:future)     { now + 3600 }
  let(:past)       { now - 3600 }

  describe '#initialize' do
    it 'sets all attributes from keyword arguments' do
      issued = now - 100
      meta   = { role: 'admin' }
      lease  = described_class.new(
        provider:   provider,
        credential: credential,
        lease_id:   lease_id,
        expires_at: future,
        renewable:  true,
        issued_at:  issued,
        metadata:   meta
      )

      expect(lease.provider).to eq(provider)
      expect(lease.credential).to eq(credential)
      expect(lease.lease_id).to eq(lease_id)
      expect(lease.expires_at).to eq(future)
      expect(lease.renewable).to be(true)
      expect(lease.issued_at).to eq(issued)
      expect(lease.metadata).to eq(meta)
    end

    it 'defaults lease_id to nil' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.lease_id).to be_nil
    end

    it 'defaults expires_at to nil' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.expires_at).to be_nil
    end

    it 'defaults renewable to false' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.renewable).to be(false)
    end

    it 'defaults issued_at to approximately now when not provided' do
      before = Time.now
      lease  = described_class.new(provider: provider, credential: credential)
      after  = Time.now
      expect(lease.issued_at).to be_between(before, after)
    end

    it 'defaults metadata to a frozen empty hash' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.metadata).to eq({})
      expect(lease.metadata).to be_frozen
    end
  end

  describe '#token' do
    it 'returns the credential' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.token).to eq(credential)
    end
  end

  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: nil)
      expect(lease.expired?).to be(false)
    end

    it 'returns false when expires_at is in the future' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: future)
      expect(lease.expired?).to be(false)
    end

    it 'returns true when expires_at is in the past' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: past)
      expect(lease.expired?).to be(true)
    end
  end

  describe '#stale?' do
    it 'returns false when expires_at is nil' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: nil)
      expect(lease.stale?).to be(false)
    end

    it 'returns false when issued_at is nil' do
      lease = described_class.new(
        provider:   provider,
        credential: credential,
        expires_at: future,
        issued_at:  nil
      )
      # issued_at defaults to Time.now inside initialize, so we must bypass it
      allow(lease).to receive(:issued_at).and_return(nil)
      expect(lease.stale?).to be(false)
    end

    it 'returns false before 50% of the TTL has elapsed' do
      # 25% through a 100-second lease
      issued = now - 25
      exp    = now + 75
      lease  = described_class.new(provider: provider, credential: credential,
                                   issued_at: issued, expires_at: exp)
      expect(lease.stale?).to be(false)
    end

    it 'returns true after 50% of the TTL has elapsed' do
      # 75% through a 100-second lease
      issued = now - 75
      exp    = now + 25
      lease  = described_class.new(provider: provider, credential: credential,
                                   issued_at: issued, expires_at: exp)
      expect(lease.stale?).to be(true)
    end

    it 'returns true at exactly the 50% mark' do
      # 50% through a 200-second lease
      issued = now - 100
      exp    = now + 100
      lease  = described_class.new(provider: provider, credential: credential,
                                   issued_at: issued, expires_at: exp)
      expect(lease.stale?).to be(true)
    end
  end

  describe '#ttl_seconds' do
    it 'returns nil when expires_at is nil' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: nil)
      expect(lease.ttl_seconds).to be_nil
    end

    it 'returns 0 when the lease has expired' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: past)
      expect(lease.ttl_seconds).to eq(0)
    end

    it 'returns a positive integer when the lease is still valid' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: future)
      expect(lease.ttl_seconds).to be_a(Integer)
      expect(lease.ttl_seconds).to be > 0
    end

    it 'approximates the remaining seconds' do
      exp   = now + 120
      lease = described_class.new(provider: provider, credential: credential, expires_at: exp)
      expect(lease.ttl_seconds).to be_between(118, 120)
    end
  end

  describe '#valid?' do
    it 'returns true when credential is present and lease is not expired' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: future)
      expect(lease.valid?).to be(true)
    end

    it 'returns true when credential is present and expires_at is nil' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: nil)
      expect(lease.valid?).to be(true)
    end

    it 'returns false when credential is nil' do
      lease = described_class.new(provider: provider, credential: nil, expires_at: future)
      expect(lease.valid?).to be(false)
    end

    it 'returns false when the lease has expired' do
      lease = described_class.new(provider: provider, credential: credential, expires_at: past)
      expect(lease.valid?).to be(false)
    end
  end

  describe '#to_h' do
    let(:issued) { now - 60 }
    let(:lease) do
      described_class.new(
        provider:   provider,
        credential: credential,
        lease_id:   lease_id,
        expires_at: future,
        renewable:  true,
        issued_at:  issued,
        metadata:   { env: 'production' }
      )
    end

    it 'returns a Hash' do
      expect(lease.to_h).to be_a(Hash)
    end

    it 'includes the provider' do
      expect(lease.to_h[:provider]).to eq(provider)
    end

    it 'includes the lease_id' do
      expect(lease.to_h[:lease_id]).to eq(lease_id)
    end

    it 'serializes expires_at as an ISO 8601 string' do
      expect(lease.to_h[:expires_at]).to eq(future.iso8601)
    end

    it 'includes renewable' do
      expect(lease.to_h[:renewable]).to be(true)
    end

    it 'serializes issued_at as an ISO 8601 string' do
      expect(lease.to_h[:issued_at]).to eq(issued.iso8601)
    end

    it 'includes the computed ttl' do
      expect(lease.to_h[:ttl]).to be_a(Integer)
      expect(lease.to_h[:ttl]).to be > 0
    end

    it 'includes the valid flag' do
      expect(lease.to_h[:valid]).to be(true)
    end

    it 'includes the metadata' do
      expect(lease.to_h[:metadata]).to eq({ env: 'production' })
    end

    it 'returns nil for expires_at when it is not set' do
      lease_no_exp = described_class.new(provider: provider, credential: credential)
      expect(lease_no_exp.to_h[:expires_at]).to be_nil
    end
  end

  describe 'edge cases' do
    it 'handles issued_at in the past with expires_at in the future correctly' do
      issued = now - 10
      exp    = now + 3590
      lease  = described_class.new(provider: provider, credential: credential,
                                   issued_at: issued, expires_at: exp)
      expect(lease.expired?).to be(false)
      expect(lease.valid?).to be(true)
      expect(lease.ttl_seconds).to be_between(3588, 3590)
      expect(lease.stale?).to be(false)
    end

    it 'freezes metadata provided at initialization' do
      meta  = { role: 'reader' }
      lease = described_class.new(provider: provider, credential: credential, metadata: meta)
      expect(lease.metadata).to be_frozen
    end

    it 'does not expose credential through token aliasing side effects' do
      lease = described_class.new(provider: provider, credential: credential)
      expect(lease.token).to equal(lease.credential)
    end
  end
end
