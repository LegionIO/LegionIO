# frozen_string_literal: true

require 'spec_helper'
require 'legion/cluster/lock'

RSpec.describe Legion::Cluster::Lock do
  # Reset the token store between examples to avoid cross-test pollution
  before do
    described_class.tokens.clear
  end

  describe '.lock_key' do
    it 'produces a consistent integer from a string' do
      key = described_class.lock_key('my_lock')
      expect(key).to be_a(Integer)
    end

    it 'is deterministic — same input produces same output' do
      expect(described_class.lock_key('some_lock')).to eq(described_class.lock_key('some_lock'))
    end

    it 'produces different keys for different names' do
      expect(described_class.lock_key('lock_a')).not_to eq(described_class.lock_key('lock_b'))
    end

    it 'stays within non-negative 32-bit range' do
      key = described_class.lock_key('test')
      expect(key).to be >= 0
      expect(key).to be <= 0x7FFFFFFF
    end
  end

  describe '.backend' do
    context 'when Legion::Cache::Redis is available with a live client' do
      let(:redis_client) { double('Redis') }

      before do
        redis_mod = Module.new
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', redis_mod)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
      end

      it 'returns :redis' do
        expect(described_class.backend).to eq(:redis)
      end
    end

    context 'when only Legion::Data is available' do
      let(:fake_db) { double('Sequel::Database') }

      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
      end

      it 'returns :postgres' do
        expect(described_class.backend).to eq(:postgres)
      end
    end

    context 'when neither cache nor DB is available' do
      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        hide_const('Legion::Data') if defined?(Legion::Data)
      end

      it 'returns :none' do
        expect(described_class.backend).to eq(:none)
      end
    end
  end

  describe '.acquire' do
    context 'when no DB connection' do
      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(nil)
      end

      it 'returns false' do
        expect(described_class.acquire(name: 'test_lock')).to be false
      end
    end

    context 'when DB is available and lock is acquired' do
      let(:result_row) { { acquired: true } }
      let(:fake_db) { instance_double('Sequel::Database') }

      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_return([result_row])
      end

      it 'returns true' do
        expect(described_class.acquire(name: 'test_lock')).to be true
      end
    end

    context 'when DB raises an error' do
      let(:fake_db) { instance_double('Sequel::Database') }

      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_raise(StandardError, 'connection lost')
      end

      it 'returns false' do
        expect(described_class.acquire(name: 'test_lock')).to be false
      end
    end

    context 'when Redis backend — key does not exist' do
      let(:redis_client) { double('Redis') }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('SET', anything, anything, 'NX', 'PX', anything).and_return('OK')
      end

      it 'returns a token string on success' do
        result = described_class.acquire(name: 'test_lock', ttl: 30)
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
    end

    context 'when Redis backend — key already exists' do
      let(:redis_client) { double('Redis') }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('SET', anything, anything, 'NX', 'PX', anything).and_return(nil)
      end

      it 'returns nil when key already exists' do
        expect(described_class.acquire(name: 'test_lock', ttl: 30)).to be_nil
      end
    end

    context 'when Redis backend — TTL is passed correctly' do
      let(:redis_client) { double('Redis') }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
      end

      it 'passes ttl in milliseconds to SET PX' do
        expect(redis_client).to receive(:call).with('SET', 'legion:lock:timed_lock', anything, 'NX', 'PX', 60_000).and_return('OK')
        described_class.acquire(name: 'timed_lock', ttl: 60)
      end
    end
  end

  describe '.release' do
    context 'when no DB connection' do
      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(nil)
      end

      it 'returns false' do
        expect(described_class.release(name: 'test_lock')).to be false
      end
    end

    context 'when DB is available and lock is released' do
      let(:result_row) { { released: true } }
      let(:fake_db) { instance_double('Sequel::Database') }

      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_return([result_row])
      end

      it 'returns true' do
        expect(described_class.release(name: 'test_lock')).to be true
      end
    end

    context 'when DB raises an error' do
      let(:fake_db) { instance_double('Sequel::Database') }

      before do
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_raise(StandardError, 'connection lost')
      end

      it 'returns false' do
        expect(described_class.release(name: 'test_lock')).to be false
      end
    end

    context 'when Redis backend — correct token' do
      let(:redis_client) { double('Redis') }
      let(:token) { 'abc123correcttoken' }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('EVAL', anything, 1, 'legion:lock:test_lock', token).and_return(1)
      end

      it 'returns true when the correct token matches' do
        expect(described_class.release(name: 'test_lock', token: token)).to be true
      end
    end

    context 'when Redis backend — wrong token' do
      let(:redis_client) { double('Redis') }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('EVAL', anything, 1, 'legion:lock:test_lock', 'wrongtoken').and_return(0)
      end

      it 'returns false when token does not match' do
        expect(described_class.release(name: 'test_lock', token: 'wrongtoken')).to be false
      end
    end
  end

  describe '.with_lock' do
    context 'when lock is acquired (PG-style true)' do
      before do
        allow(described_class).to receive(:acquire).and_return(true)
        allow(described_class).to receive(:release)
      end

      it 'yields the block' do
        yielded = false
        described_class.with_lock(name: 'test_lock') { yielded = true }
        expect(yielded).to be true
      end

      it 'releases the lock after yielding' do
        described_class.with_lock(name: 'test_lock') { nil }
        expect(described_class).to have_received(:release).with(name: 'test_lock', token: nil)
      end
    end

    context 'when lock is unavailable' do
      before do
        allow(described_class).to receive(:acquire).and_return(false)
        allow(described_class).to receive(:release)
      end

      it 'does not yield' do
        yielded = false
        described_class.with_lock(name: 'test_lock') { yielded = true }
        expect(yielded).to be false
      end

      it 'does not call release' do
        described_class.with_lock(name: 'test_lock') { nil }
        expect(described_class).not_to have_received(:release)
      end
    end

    context 'when Redis backend — lock acquired' do
      let(:redis_client) { double('Redis') }
      let(:token) { 'deadbeefdeadbeef' }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('SET', anything, anything, 'NX', 'PX', anything).and_return('OK')
        allow(redis_client).to receive(:call).with('EVAL', anything, 1, anything, anything).and_return(1)
        allow(SecureRandom).to receive(:hex).with(16).and_return(token)
      end

      it 'yields the block' do
        yielded = false
        described_class.with_lock(name: 'redis_lock') { yielded = true }
        expect(yielded).to be true
      end

      it 'releases with the acquired token' do
        described_class.with_lock(name: 'redis_lock') { nil }
        expect(redis_client).to have_received(:call).with('EVAL', anything, 1, 'legion:lock:redis_lock', token)
      end
    end

    context 'when Redis backend — lock unavailable' do
      let(:redis_client) { double('Redis') }

      before do
        stub_const('Legion::Cache', Module.new)
        stub_const('Legion::Cache::Redis', Module.new)
        allow(Legion::Cache::Redis).to receive(:client).and_return(redis_client)
        allow(redis_client).to receive(:call).with('SET', anything, anything, 'NX', 'PX', anything).and_return(nil)
      end

      it 'does not yield when lock is unavailable' do
        yielded = false
        described_class.with_lock(name: 'redis_lock') { yielded = true }
        expect(yielded).to be false
      end
    end
  end
end
