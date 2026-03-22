# frozen_string_literal: true

require 'spec_helper'
require 'legion/lock'

RSpec.describe Legion::Lock do
  let(:mock_redis) { instance_double('Redis') }
  let(:mock_pool) { instance_double('ConnectionPool') }

  before do
    pool = mock_pool
    redis = mock_redis
    allow(pool).to receive(:with).and_yield(redis)
    cache_mod = Module.new
    cache_mod.define_singleton_method(:client) { pool }
    stub_const('Legion::Cache', cache_mod)
  end

  describe '.acquire' do
    it 'returns a UUID token when SET NX succeeds' do
      allow(mock_redis).to receive(:set).and_return(true)
      token = described_class.acquire('test-lock')
      expect(token).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'returns nil when SET NX fails' do
      allow(mock_redis).to receive(:set).and_return(false)
      expect(described_class.acquire('test-lock')).to be_nil
    end

    it 'passes NX and PX options to Redis SET' do
      allow(mock_redis).to receive(:set).and_return(true)
      described_class.acquire('test-lock', ttl: 5000)
      expect(mock_redis).to have_received(:set).with('legion:lock:test-lock', anything, nx: true, px: 5000)
    end

    it 'returns nil when Redis is unavailable' do
      pool = mock_pool
      allow(pool).to receive(:with).and_raise(StandardError, 'connection refused')
      expect(described_class.acquire('test-lock')).to be_nil
    end
  end

  describe '.release' do
    it 'returns true when token matches' do
      allow(mock_redis).to receive(:eval).and_return(1)
      expect(described_class.release('test-lock', 'my-token')).to be true
    end

    it 'returns false when token does not match' do
      allow(mock_redis).to receive(:eval).and_return(0)
      expect(described_class.release('test-lock', 'wrong-token')).to be false
    end

    it 'uses Lua script with correct key and argv' do
      allow(mock_redis).to receive(:eval).and_return(1)
      described_class.release('test-lock', 'my-token')
      expect(mock_redis).to have_received(:eval).with(
        described_class::RELEASE_SCRIPT,
        keys: ['legion:lock:test-lock'],
        argv: ['my-token']
      )
    end

    it 'returns false when Redis is unavailable' do
      pool = mock_pool
      allow(pool).to receive(:with).and_raise(StandardError, 'connection refused')
      expect(described_class.release('test-lock', 'tok')).to be false
    end
  end

  describe '.with_lock' do
    it 'yields when lock is acquired' do
      allow(mock_redis).to receive(:set).and_return(true)
      allow(mock_redis).to receive(:eval).and_return(1)
      expect { |b| described_class.with_lock('test-lock', &b) }.to yield_control
    end

    it 'raises NotAcquired when lock cannot be obtained' do
      allow(mock_redis).to receive(:set).and_return(false)
      expect { described_class.with_lock('test-lock') { nil } }.to raise_error(Legion::Lock::NotAcquired)
    end

    it 'releases the lock even when the block raises' do
      allow(mock_redis).to receive(:set).and_return(true)
      allow(mock_redis).to receive(:eval).and_return(1)
      begin
        described_class.with_lock('test-lock') { raise 'boom' }
      rescue RuntimeError
        nil
      end
      expect(mock_redis).to have_received(:eval).with(described_class::RELEASE_SCRIPT, anything)
    end
  end

  describe '.extend_lock' do
    it 'returns true when token matches and TTL is reset' do
      allow(mock_redis).to receive(:eval).and_return(1)
      expect(described_class.extend_lock('test-lock', 'my-token', ttl: 10_000)).to be true
    end

    it 'returns false when token does not match' do
      allow(mock_redis).to receive(:eval).and_return(0)
      expect(described_class.extend_lock('test-lock', 'wrong', ttl: 10_000)).to be false
    end
  end

  describe '.locked?' do
    it 'returns true when key exists' do
      allow(mock_redis).to receive(:exists?).and_return(true)
      expect(described_class.locked?('test-lock')).to be true
    end

    it 'returns false when key does not exist' do
      allow(mock_redis).to receive(:exists?).and_return(false)
      expect(described_class.locked?('test-lock')).to be false
    end
  end
end
