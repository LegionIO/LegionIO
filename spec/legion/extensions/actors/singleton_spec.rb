# frozen_string_literal: true

require 'spec_helper'
require 'legion/lock'
require 'legion/cluster/lock'
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
    allow(Legion::Settings).to receive(:[]).with(:cluster).and_return({ singleton_enabled: true })
    allow(Legion::Cluster::Lock).to receive(:acquire).and_return('cluster-tok-123')
    allow(Legion::Cluster::Lock).to receive(:extend_lock).and_return(true)
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
    context 'when singleton_enabled is false (default)' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:cluster).and_return({ singleton_enabled: false })
      end

      it 'passes through without acquiring any lock' do
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be true
        expect(Legion::Cluster::Lock).not_to have_received(:acquire)
        expect(Legion::Lock).not_to have_received(:acquire)
      end
    end

    context 'when Legion::Settings is not defined' do
      it 'falls through without acquiring any lock' do
        hide_const('Legion::Settings')
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be true
      end
    end

    context 'when singleton_enabled is true and Cluster::Lock is available' do
      it 'uses Cluster::Lock instead of Legion::Lock' do
        actor.send(:skip_or_run) { nil }
        expect(Legion::Cluster::Lock).to have_received(:acquire)
        expect(Legion::Lock).not_to have_received(:acquire)
      end

      it 'extends via Cluster::Lock on subsequent ticks' do
        actor.send(:skip_or_run) { nil }
        actor.send(:skip_or_run) { nil }
        expect(Legion::Cluster::Lock).to have_received(:extend_lock).at_least(:once)
      end

      it 'skips execution when Cluster::Lock cannot be acquired' do
        allow(Legion::Cluster::Lock).to receive(:acquire).and_return(nil)
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be false
      end

      it 'executes the block when lock is held' do
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be true
      end

      it 're-acquires via Cluster::Lock when extend fails' do
        actor.send(:skip_or_run) { nil }
        allow(Legion::Cluster::Lock).to receive(:extend_lock).and_return(false)
        allow(Legion::Cluster::Lock).to receive(:acquire).and_return('cluster-tok-456')
        actor.send(:skip_or_run) { nil }
        expect(Legion::Cluster::Lock).to have_received(:acquire).at_least(:twice)
      end
    end

    context 'when singleton_enabled is true and Cluster::Lock is not available' do
      before do
        hide_const('Legion::Cluster::Lock')
      end

      it 'falls back to Legion::Lock' do
        actor.send(:skip_or_run) { nil }
        expect(Legion::Lock).to have_received(:acquire)
      end

      it 'extends via Legion::Lock on subsequent ticks' do
        actor.send(:skip_or_run) { nil }
        actor.send(:skip_or_run) { nil }
        expect(Legion::Lock).to have_received(:extend_lock).at_least(:once)
      end

      it 'skips execution when Legion::Lock cannot be acquired' do
        allow(Legion::Lock).to receive(:acquire).and_return(nil)
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be false
      end

      it 're-acquires when extend fails' do
        actor.send(:skip_or_run) { nil }
        allow(Legion::Lock).to receive(:extend_lock).and_return(false)
        allow(Legion::Lock).to receive(:acquire).and_return('tok-456')
        actor.send(:skip_or_run) { nil }
        expect(Legion::Lock).to have_received(:acquire).at_least(:twice)
      end

      it 'falls through when neither lock is defined' do
        hide_const('Legion::Lock')
        executed = false
        actor.send(:skip_or_run) { executed = true }
        expect(executed).to be true
      end
    end
  end
end
