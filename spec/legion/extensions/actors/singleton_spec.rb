# frozen_string_literal: true

require 'spec_helper'
require 'legion/lock'
require 'legion/extensions/actors/singleton'

module TestExt
  module Actors
    class Cleanup
      def initialize(**_opts); end
      def time = 10

      include Legion::Extensions::Actors::Singleton

      private

      def skip_or_run
        yield
      end
    end
  end
end

RSpec.describe Legion::Extensions::Actors::Singleton do
  let(:actor) { TestExt::Actors::Cleanup.new }

  before do
    allow(Legion::Lock).to receive(:acquire).and_return('tok-123')
    allow(Legion::Lock).to receive(:extend_lock).and_return(true)
    allow(Legion::Lock).to receive(:release).and_return(true)
  end

  describe '#singleton_role' do
    it 'derives role from class name' do
      expect(actor.singleton_role).to eq('testext_actors_cleanup')
    end
  end

  describe '#singleton_ttl' do
    it 'returns at least 30 seconds' do
      expect(actor.singleton_ttl).to be >= 30
    end

    it 'returns 3x the interval when interval is large' do
      allow(actor).to receive(:time).and_return(60)
      expect(actor.singleton_ttl).to eq(180)
    end
  end

  describe 'ExecutionGuard#skip_or_run' do
    it 'acquires leader lock before executing' do
      actor.send(:skip_or_run) { nil }
      expect(Legion::Lock).to have_received(:acquire)
    end

    it 'extends the lock on subsequent ticks' do
      actor.send(:skip_or_run) { nil } # acquires + extends
      actor.send(:skip_or_run) { nil } # extends again
      expect(Legion::Lock).to have_received(:extend_lock).at_least(:twice)
    end

    it 'skips execution when lock cannot be acquired' do
      allow(Legion::Lock).to receive(:acquire).and_return(nil)
      executed = false
      actor.send(:skip_or_run) { executed = true }
      expect(executed).to be false
    end

    it 'executes the block when lock is held' do
      executed = false
      actor.send(:skip_or_run) { executed = true }
      expect(executed).to be true
    end

    it 're-acquires when extend fails' do
      actor.send(:skip_or_run) { nil } # first acquire
      allow(Legion::Lock).to receive(:extend_lock).and_return(false)
      allow(Legion::Lock).to receive(:acquire).and_return('tok-456')
      actor.send(:skip_or_run) { nil }
      expect(Legion::Lock).to have_received(:acquire).at_least(:twice)
    end

    it 'falls through without Legion::Lock defined' do
      hide_const('Legion::Lock')
      executed = false
      actor.send(:skip_or_run) { executed = true }
      expect(executed).to be true
    end
  end
end
