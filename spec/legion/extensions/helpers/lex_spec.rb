# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Lex do
  let(:test_module) do
    Module.new do
      extend self

      def settings
        @settings ||= { functions: {}, runners: {} }
      end

      def respond_to?(name, *)
        return true if %i[my_func other_func].include?(name)

        super
      end

      def actor_name
        'test_runner'
      end

      def log
        @log ||= Logger.new(File::NULL)
      end

      include Legion::Extensions::Helpers::Lex
    end
  end

  describe 'new per-function DSL methods' do
    it 'stores function_outputs' do
      test_module.function_outputs(:my_func, { properties: { result: { type: 'string' } } })
      expect(test_module.settings[:functions][:my_func][:outputs]).to eq({ properties: { result: { type: 'string' } } })
    end

    it 'stores function_category' do
      test_module.function_category(:my_func, :codegen)
      expect(test_module.settings[:functions][:my_func][:category]).to eq(:codegen)
    end

    it 'stores function_tags' do
      test_module.function_tags(:my_func, %i[generation gap])
      expect(test_module.settings[:functions][:my_func][:tags]).to eq(%i[generation gap])
    end

    it 'stores function_risk_tier' do
      test_module.function_risk_tier(:my_func, :medium)
      expect(test_module.settings[:functions][:my_func][:risk_tier]).to eq(:medium)
    end

    it 'stores function_idempotent' do
      test_module.function_idempotent(:my_func, false)
      expect(test_module.settings[:functions][:my_func][:idempotent]).to eq(false)
    end

    it 'stores function_requires' do
      test_module.function_requires(:my_func, ['Legion::LLM'])
      expect(test_module.settings[:functions][:my_func][:requires]).to eq(['Legion::LLM'])
    end

    it 'stores function_expose' do
      test_module.function_expose(:my_func, true)
      expect(test_module.settings[:functions][:my_func][:expose]).to eq(true)
    end
  end

  describe 'ClassMethods' do
    let(:test_class) do
      Class.new do
        include Legion::Extensions::Helpers::Lex
      end
    end

    describe '.expose_as_mcp_tool' do
      it 'sets the class-level default when called with a value' do
        test_class.expose_as_mcp_tool(true)
        expect(test_class.expose_as_mcp_tool).to eq(true)
      end

      it 'defaults to false when Settings not available' do
        expect(test_class.expose_as_mcp_tool).to eq(false)
      end

      it 'reads from Settings when available and not explicitly set' do
        stub_const('Legion::Settings', Module.new do
          def self.dig(*keys)
            true if keys == %i[mcp auto_expose_runners]
          end
        end)
        fresh_class = Class.new { include Legion::Extensions::Helpers::Lex }
        expect(fresh_class.expose_as_mcp_tool).to eq(true)
      end
    end

    describe '.mcp_tool_prefix' do
      it 'sets and reads the prefix' do
        test_class.mcp_tool_prefix('legion.codegen')
        expect(test_class.mcp_tool_prefix).to eq('legion.codegen')
      end

      it 'returns nil by default' do
        expect(test_class.mcp_tool_prefix).to be_nil
      end
    end
  end

  describe '3-tier exposure precedence' do
    it 'function_expose overrides class-level expose_as_mcp_tool' do
      test_module.function_expose(:my_func, false)
      # Even if class-level says true, per-function says false
      expect(test_module.settings[:functions][:my_func][:expose]).to eq(false)
    end
  end
end
