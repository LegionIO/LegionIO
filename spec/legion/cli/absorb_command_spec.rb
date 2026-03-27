# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/error'

# Stub extension modules before loading the command
module Legion
  module Extensions
    module Actors
      module AbsorberDispatch
        class << self
          attr_accessor :test_dispatch_result
        end

        def self.dispatch(**)
          Legion::Extensions::Actors::AbsorberDispatch.test_dispatch_result
        end
      end
    end

    module Absorbers
      module PatternMatcher
        class << self
          attr_accessor :test_list_result, :test_resolve_result
        end

        def self.list
          Legion::Extensions::Absorbers::PatternMatcher.test_list_result || []
        end

        def self.resolve(_input)
          Legion::Extensions::Absorbers::PatternMatcher.test_resolve_result
        end
      end
    end
  end
end

require 'legion/cli/absorb_command'

RSpec.describe Legion::CLI::AbsorbCommand do
  let(:command) { described_class.new }

  describe '.exit_on_failure?' do
    it 'returns true' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe '#list' do
    it 'responds to list' do
      expect(command).to respond_to(:list)
    end
  end

  describe '#url' do
    it 'responds to url' do
      expect(command).to respond_to(:url)
    end
  end

  describe '#resolve' do
    it 'responds to resolve' do
      expect(command).to respond_to(:resolve)
    end
  end
end
