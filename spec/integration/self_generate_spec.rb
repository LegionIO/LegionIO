# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Self-generating functions integration', :integration do
  describe 'function metadata DSL' do
    it 'stores and reads function metadata' do
      skip('Legion::Extensions::Helpers::Lex not loaded') unless defined?(Legion::Extensions::Helpers::Lex)

      # Use a real module under Legion::Extensions namespace so that Lex helpers resolve
      # segments/log/settings correctly via the Base mixin.
      mod = Module.new do
        extend self

        def settings
          @settings ||= { functions: {} }
        end

        def log
          @log ||= Logger.new(File::NULL)
        end

        def respond_to?(name, include_private: false)
          return true if name == :my_func

          super
        end

        def my_func; end

        include Legion::Extensions::Helpers::Lex
      end

      mod.function_desc(:my_func, 'Test function')
      mod.function_expose(:my_func, true)
      mod.function_category(:my_func, :codegen)
      mod.function_tags(:my_func, %i[test integration])

      func = mod.settings[:functions][:my_func]
      expect(func[:desc]).to eq('Test function')
      expect(func[:expose]).to be true
      expect(func[:category]).to eq(:codegen)
      expect(func[:tags]).to eq(%i[test integration])
    end
  end
end
