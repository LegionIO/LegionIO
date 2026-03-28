# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Lex do
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
end
