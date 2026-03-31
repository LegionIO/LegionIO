# frozen_string_literal: true

require 'spec_helper'
require 'legion/process'
require 'concurrent/atomic/atomic_boolean'

RSpec.describe Legion::Process do
  let(:options) { {} }
  let(:process) { described_class.new(options) }

  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
  end

  after do
    described_class.quit_flag = nil
  end

  describe '#quit' do
    it 'returns false when AtomicBoolean is false' do
      process.instance_variable_set(:@quit, Concurrent::AtomicBoolean.new(false))
      expect(process.quit).to be false
    end

    it 'returns true when AtomicBoolean is true' do
      process.instance_variable_set(:@quit, Concurrent::AtomicBoolean.new(true))
      expect(process.quit).to be true
    end

    it 'falls back to raw value when not AtomicBoolean' do
      process.instance_variable_set(:@quit, nil)
      expect(process.quit).to be_nil
    end
  end

  describe '.quit_flag' do
    it 'is a class-level accessor' do
      flag = Concurrent::AtomicBoolean.new(false)
      described_class.quit_flag = flag
      expect(described_class.quit_flag).to eq flag
    end

    it 'can be signaled from external code' do
      flag = Concurrent::AtomicBoolean.new(false)
      described_class.quit_flag = flag
      described_class.quit_flag.make_true
      expect(flag.true?).to be true
    end
  end

  describe '#trap_signals' do
    it 'installs traps for SIGINT, SIGTERM, and SIGHUP' do
      process.instance_variable_set(:@quit, Concurrent::AtomicBoolean.new(false))
      expect { process.trap_signals }.not_to raise_error
    end
  end

  describe '#retrap_after_puma' do
    it 'spawns a persistent thread that re-registers signal traps' do
      process.instance_variable_set(:@quit, Concurrent::AtomicBoolean.new(false))
      process.retrap_after_puma
      thread = process.instance_variable_get(:@retrap_thread)
      expect(thread).to be_a(Thread)
      expect(thread).to be_alive
      thread.kill
    end
  end

  describe 'AtomicBoolean thread safety' do
    it 'handles concurrent make_true from multiple threads' do
      flag = Concurrent::AtomicBoolean.new(false)
      threads = 5.times.map { Thread.new { flag.make_true } }
      threads.each(&:join)
      expect(flag.true?).to be true
    end
  end
end
