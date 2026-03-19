# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'legion/mcp/observer'
require 'legion/mcp/embedding_index'

require 'thor'

unless defined?(Legion::CLI::Main)
  module Legion
    module CLI
      class Main < Thor; end
    end
  end
end

require 'legion/cli/observe_command'

RSpec.describe Legion::CLI::ObserveCommand do
  before(:each) do
    Legion::MCP::Observer.reset!
    Legion::MCP::EmbeddingIndex.reset!
  end

  describe '#stats' do
    let(:command) { described_class.new }

    before do
      allow(command).to receive(:options).and_return({ 'json' => false })
    end

    it 'outputs total calls' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      expect { command.stats }.to output(/Total Calls.*1/).to_stdout
    end

    it 'outputs tool count' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      Legion::MCP::Observer.record(tool_name: 'legion.list_tasks', duration_ms: 50, success: true)
      expect { command.stats }.to output(/Tools Used.*2/).to_stdout
    end

    it 'outputs failure rate' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: false)
      expect { command.stats }.to output(/Failure Rate.*100\.0%/).to_stdout
    end

    it 'outputs top tools table' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      expect { command.stats }.to output(/Top Tools/).to_stdout
    end

    it 'outputs JSON when --json flag is set' do
      allow(command).to receive(:options).and_return({ 'json' => true })
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      output = StringIO.new
      $stdout = output
      command.stats
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed['total_calls']).to eq(1)
    end

    it 'handles empty stats gracefully' do
      expect { command.stats }.to output(/Total Calls.*0/).to_stdout
    end
  end

  describe '#recent' do
    let(:command) { described_class.new }

    before do
      allow(command).to receive(:options).and_return({ 'json' => false, 'limit' => 10 })
    end

    it 'outputs recent tool calls' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      expect { command.recent }.to output(/legion\.run_task/).to_stdout
    end

    it 'shows empty message when no calls recorded' do
      expect { command.recent }.to output(/No recent tool calls recorded/).to_stdout
    end

    it 'shows status OK for successful calls' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      expect { command.recent }.to output(/OK/).to_stdout
    end

    it 'shows status FAIL for failed calls' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: false)
      expect { command.recent }.to output(/FAIL/).to_stdout
    end

    it 'outputs JSON when --json flag is set' do
      allow(command).to receive(:options).and_return({ 'json' => true, 'limit' => 10 })
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      output = StringIO.new
      $stdout = output
      command.recent
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed).to be_an(Array)
      expect(parsed.first['tool_name']).to eq('legion.run_task')
    end
  end

  describe '#reset' do
    let(:command) { described_class.new }

    it 'clears observer data when confirmed' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      allow($stdin).to receive(:gets).and_return("yes\n")
      command.reset
      expect(Legion::MCP::Observer.stats[:total_calls]).to eq(0)
    end

    it 'does not clear when user declines' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      allow($stdin).to receive(:gets).and_return("no\n")
      command.reset
      expect(Legion::MCP::Observer.stats[:total_calls]).to eq(1)
    end
  end

  describe '#embeddings' do
    let(:command) { described_class.new }

    before do
      allow(command).to receive(:options).and_return({ 'json' => false })
      Legion::MCP::EmbeddingIndex.reset!
    end

    it 'outputs index size' do
      expect { command.embeddings }.to output(/Index Size.*0/).to_stdout
    end

    it 'outputs coverage' do
      expect { command.embeddings }.to output(/Coverage/).to_stdout
    end

    it 'shows populated status when index has entries' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::EmbeddingIndex.build_from_tool_data(
        [{ name: 'legion.run_task', description: 'Execute', params: [] }],
        embedder: fake_embedder
      )
      expect { command.embeddings }.to output(/Index Size.*1/).to_stdout
    end

    it 'outputs JSON when --json flag is set' do
      allow(command).to receive(:options).and_return({ 'json' => true })
      output = StringIO.new
      $stdout = output
      command.embeddings
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed).to have_key('index_size')
      expect(parsed).to have_key('coverage')
    end
  end
end
