# frozen_string_literal: true

require 'spec_helper'
require 'legion/cluster/lock'

RSpec.describe Legion::Cluster::Lock do
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

  describe '.acquire' do
    context 'when no DB connection' do
      before do
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
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_raise(StandardError, 'connection lost')
      end

      it 'returns false' do
        expect(described_class.acquire(name: 'test_lock')).to be false
      end
    end
  end

  describe '.release' do
    context 'when no DB connection' do
      before do
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
        stub_const('Legion::Data', Module.new)
        allow(Legion::Data).to receive(:connection).and_return(fake_db)
        allow(fake_db).to receive(:fetch).and_raise(StandardError, 'connection lost')
      end

      it 'returns false' do
        expect(described_class.release(name: 'test_lock')).to be false
      end
    end
  end

  describe '.with_lock' do
    context 'when lock is acquired' do
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
        expect(described_class).to have_received(:release).with(name: 'test_lock')
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
  end
end
