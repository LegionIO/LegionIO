# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do
  before(:each) { Legion::MCP::Observer.reset! }

  # Build stub tool classes that behave like real MCP::Tool subclasses
  let(:tool_alpha) do
    Class.new(MCP::Tool) do
      tool_name 'legion.alpha'
      description 'Alpha tool'
      input_schema(properties: {})
      define_singleton_method(:call) { MCP::Tool::Response.new([]) }
    end
  end

  let(:tool_beta) do
    Class.new(MCP::Tool) do
      tool_name 'legion.beta'
      description 'Beta tool'
      input_schema(properties: {})
      define_singleton_method(:call) { MCP::Tool::Response.new([]) }
    end
  end

  let(:tool_gamma) do
    Class.new(MCP::Tool) do
      tool_name 'legion.gamma'
      description 'Gamma tool'
      input_schema(properties: {})
      define_singleton_method(:call) { MCP::Tool::Response.new([]) }
    end
  end

  let(:stub_tools) { [tool_alpha, tool_beta, tool_gamma] }

  describe '.build_filtered_tool_list' do
    context 'with no observation data' do
      it 'returns all tools when no usage has been recorded' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)
        result = described_class.build_filtered_tool_list
        expect(result).to match_array(stub_tools)
      end

      it 'returns tool class objects, not strings' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)
        result = described_class.build_filtered_tool_list
        result.each { |tc| expect(tc).to be_a(Class) }
      end
    end

    context 'when one tool has been used more than others' do
      it 'ranks the most-called tool first' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)

        10.times { Legion::MCP::Observer.record(tool_name: 'legion.beta', duration_ms: 10, success: true) }
        Legion::MCP::Observer.record(tool_name: 'legion.alpha', duration_ms: 5, success: true)

        result = described_class.build_filtered_tool_list
        expect(result.first).to eq(tool_beta)
      end

      it 'places unused tools after used tools' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)

        5.times { Legion::MCP::Observer.record(tool_name: 'legion.alpha', duration_ms: 10, success: true) }

        result = described_class.build_filtered_tool_list
        used_index   = result.index(tool_alpha)
        unused_index = result.index(tool_gamma)
        expect(used_index).to be < unused_index
      end
    end

    context 'with keyword boost' do
      it 'places keyword-matching tools higher' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)

        result = described_class.build_filtered_tool_list(keywords: ['beta'])
        expect(result.first).to eq(tool_beta)
      end

      it 'accepts multiple keywords and places tool matching more keywords higher' do
        stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)

        # tool_alpha matches both 'alpha' and 'legion' (2/2 = 1.0), beta matches only 'legion' (1/2 = 0.5)
        result = described_class.build_filtered_tool_list(keywords: %w[alpha legion])
        alpha_index = result.index(tool_alpha)
        beta_index  = result.index(tool_beta)
        expect(alpha_index).to be < beta_index
      end
    end

    it 'preserves all tools in the result regardless of observation data' do
      stub_const('Legion::MCP::Server::TOOL_CLASSES', stub_tools)

      5.times { Legion::MCP::Observer.record(tool_name: 'legion.alpha', duration_ms: 10, success: true) }

      result = described_class.build_filtered_tool_list
      expect(result.size).to eq(stub_tools.size)
      expect(result).to include(tool_alpha, tool_beta, tool_gamma)
    end
  end
end
