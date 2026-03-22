# frozen_string_literal: true

require 'spec_helper'
require 'legion/leader'

RSpec.describe Legion::Leader do
  before do
    described_class.reset!
    allow(Legion::Lock).to receive(:acquire).and_return('test-token')
    allow(Legion::Lock).to receive(:release).and_return(true)
    allow(Legion::Lock).to receive(:extend_lock).and_return(true)
    allow(Legion::Lock).to receive(:locked?).and_return(true)
  end

  after { described_class.reset! }

  describe '.elect' do
    it 'returns token on success' do
      expect(described_class.elect(:scheduler)).to eq('test-token')
    end

    it 'returns nil when lock not acquired' do
      allow(Legion::Lock).to receive(:acquire).and_return(nil)
      expect(described_class.elect(:scheduler)).to be_nil
    end

    it 'converts ttl seconds to milliseconds' do
      described_class.elect(:scheduler, ttl: 15)
      expect(Legion::Lock).to have_received(:acquire).with('leader:scheduler', ttl: 15_000)
    end

    it 'stores the leadership entry' do
      described_class.elect(:scheduler)
      expect(described_class.leader?(:scheduler)).to be true
    end
  end

  describe '.leader?' do
    it 'returns false when role not elected' do
      expect(described_class.leader?(:unknown)).to be false
    end

    it 'returns true when role is elected and lock exists' do
      described_class.elect(:scheduler)
      expect(described_class.leader?(:scheduler)).to be true
    end

    it 'returns false when lock has expired' do
      described_class.elect(:scheduler)
      allow(Legion::Lock).to receive(:locked?).and_return(false)
      expect(described_class.leader?(:scheduler)).to be false
    end
  end

  describe '.resign' do
    it 'releases the lock' do
      described_class.elect(:scheduler)
      described_class.resign(:scheduler)
      expect(Legion::Lock).to have_received(:release).with('leader:scheduler', 'test-token')
    end

    it 'returns false when not a leader' do
      expect(described_class.resign(:unknown)).to be false
    end

    it 'clears the leadership entry' do
      described_class.elect(:scheduler)
      described_class.resign(:scheduler)
      expect(described_class.leader?(:scheduler)).to be false
    end
  end

  describe '.with_leadership' do
    it 'yields when leadership is acquired' do
      expect { |b| described_class.with_leadership(:scheduler, ttl: 30, &b) }.to yield_control
    end

    it 'raises NotAcquired when election fails' do
      allow(Legion::Lock).to receive(:acquire).and_return(nil)
      expect { described_class.with_leadership(:scheduler) { nil } }.to raise_error(Legion::Lock::NotAcquired)
    end

    it 'resigns after the block completes' do
      described_class.with_leadership(:scheduler) { nil }
      expect(Legion::Lock).to have_received(:release)
    end

    it 'resigns even when the block raises' do
      begin
        described_class.with_leadership(:scheduler) { raise 'boom' }
      rescue RuntimeError
        nil
      end
      expect(Legion::Lock).to have_received(:release)
    end
  end

  describe '.reset!' do
    it 'resigns all leaders' do
      described_class.elect(:scheduler)
      described_class.elect(:archiver)
      described_class.reset!
      expect(described_class.leader?(:scheduler)).to be false
      expect(described_class.leader?(:archiver)).to be false
    end
  end
end
