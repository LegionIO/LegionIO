# frozen_string_literal: true

require 'spec_helper'

unless defined?(Legion::Logging)
  module Legion
    module Logging
      def self.debug(_msg); end
      def self.info(_msg); end
      def self.warn(_msg); end
      def self.error(_msg); end
    end
  end
end

unless defined?(Legion::Extensions::Helpers::Lex)
  module Legion
    module Extensions
      module Helpers
        module Lex
          def lex_name = 'test'
          def runner_class = Object
          def runner_function = 'run'
          def runner_name = 'test'
        end
      end
    end
  end
end

unless defined?(Concurrent::TimerTask)
  module Concurrent
    class TimerTask
      def initialize(**_opts, &); end
      def execute; end
      def shutdown; end

      def respond_to?(_method, *) = true
    end
  end
end

require 'legion/extensions/actors/fingerprint'
require 'legion/extensions/actors/base'
require 'legion/extensions/actors/every'

RSpec.describe Legion::Extensions::Actors::Every do
  describe '#skip_if_unchanged?' do
    it 'defaults to false' do
      actor = described_class.new
      expect(actor.skip_if_unchanged?).to be false
    end
  end

  describe 'subclass with skip_if_unchanged enabled' do
    let(:actor_class) do
      Class.new(Legion::Extensions::Actors::Every) do
        def skip_if_unchanged? = true
        def time = 30
      end
    end

    it 'responds to skip_or_run' do
      actor = actor_class.new
      expect(actor).to respond_to(:skip_or_run)
    end

    it 'skips second run when fingerprint is stable' do
      actor = actor_class.new
      allow(actor).to receive(:fingerprint_source).and_return('stable')
      runs = 0
      actor.skip_or_run { runs += 1 }
      actor.skip_or_run { runs += 1 }
      expect(runs).to eq(1)
    end

    it 'runs again when fingerprint changes' do
      actor = actor_class.new
      sources = %w[v1 v2]
      idx = 0
      allow(actor).to receive(:fingerprint_source) { sources[idx] }
      runs = 0
      2.times do
        actor.skip_or_run { runs += 1 }
        idx += 1
      end
      expect(runs).to eq(2)
    end
  end
end
