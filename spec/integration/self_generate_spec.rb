# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Self-generating functions integration', :integration do
  describe 'Helpers::Lex module inclusion' do
    it 'includes without error' do
      skip('Legion::Extensions::Helpers::Lex not loaded') unless defined?(Legion::Extensions::Helpers::Lex)

      mod = Module.new do
        extend self

        def settings
          @settings ||= { functions: {}, runners: {} }
        end

        def log
          @log ||= Logger.new(File::NULL)
        end

        def actor_name
          'test_runner'
        end

        include Legion::Extensions::Helpers::Lex
      end

      expect(mod).to respond_to(:runner_desc)
    end
  end
end
