# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::DiscoverTools do
  let(:compressed_catalog) do
    [
      { category: :tasks, summary: 'Create and manage tasks.', tool_count: 2, tools: %w[legion.run_task legion.list_tasks] },
      { category: :extensions, summary: 'Manage extensions.', tool_count: 1, tools: ['legion.list_extensions'] }
    ]
  end

  let(:category_result) do
    {
      category: :tasks,
      summary:  'Create and manage tasks.',
      tools:    [
        { name: 'legion.run_task', description: 'Execute a task.', params: %w[task params] },
        { name: 'legion.list_tasks', description: 'List all tasks.', params: ['limit'] }
      ]
    }
  end

  let(:match_results) do
    [
      { name: 'legion.run_task', description: 'Execute a task.', score: 3 },
      { name: 'legion.list_tasks', description: 'List all tasks.', score: 1 }
    ]
  end

  before do
    allow(Legion::MCP::ContextCompiler).to receive(:compressed_catalog).and_return(compressed_catalog)
    allow(Legion::MCP::ContextCompiler).to receive(:category_tools).and_return(nil)
    allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return(match_results)
  end

  describe '.call' do
    context 'with no arguments' do
      it 'returns the full compressed catalog' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'calls ContextCompiler.compressed_catalog' do
        expect(Legion::MCP::ContextCompiler).to receive(:compressed_catalog).and_return(compressed_catalog)
        described_class.call
      end

      it 'response JSON contains catalog data' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        # symbol values serialize to strings through JSON round-trip
        expect(data.first[:category].to_s).to eq('tasks')
      end
    end

    context 'with category argument' do
      context 'when category is valid' do
        before do
          allow(Legion::MCP::ContextCompiler).to receive(:category_tools).with(:tasks).and_return(category_result)
        end

        it 'returns category tools without error' do
          response = described_class.call(category: 'tasks')
          expect(response.error?).to be false
        end

        it 'calls category_tools with symbolized category' do
          expect(Legion::MCP::ContextCompiler).to receive(:category_tools).with(:tasks).and_return(category_result)
          described_class.call(category: 'tasks')
        end

        it 'response JSON contains category and tools keys' do
          response = described_class.call(category: 'tasks')
          data = Legion::JSON.load(response.content.first[:text])
          expect(data).to have_key(:category)
          expect(data).to have_key(:tools)
        end
      end

      context 'when category is unknown' do
        before do
          allow(Legion::MCP::ContextCompiler).to receive(:category_tools).with(:unknown_xyz).and_return(nil)
        end

        it 'returns an error response' do
          response = described_class.call(category: 'unknown_xyz')
          expect(response.error?).to be true
        end

        it 'error message includes the category name' do
          response = described_class.call(category: 'unknown_xyz')
          data = Legion::JSON.load(response.content.first[:text])
          expect(data[:error]).to include('unknown_xyz')
        end
      end
    end

    context 'with intent argument' do
      it 'returns matched tools without error' do
        response = described_class.call(intent: 'run a task')
        expect(response.error?).to be false
      end

      it 'calls match_tools with the intent and limit 5' do
        expect(Legion::MCP::ContextCompiler).to receive(:match_tools).with('run a task', limit: 5).and_return(match_results)
        described_class.call(intent: 'run a task')
      end

      it 'response JSON wraps results in matched_tools key' do
        response = described_class.call(intent: 'run a task')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:matched_tools)
        expect(data[:matched_tools]).to be_an(Array)
      end

      it 'matched_tools array contains the returned results' do
        response = described_class.call(intent: 'run a task')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:matched_tools].first[:name]).to eq('legion.run_task')
      end
    end

    context 'when ContextCompiler raises an error' do
      before do
        allow(Legion::MCP::ContextCompiler).to receive(:compressed_catalog).and_raise(StandardError, 'index error')
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('index error')
      end
    end
  end
end
