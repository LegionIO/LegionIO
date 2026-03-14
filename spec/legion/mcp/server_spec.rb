# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do
  describe '.build' do
    subject(:server) { described_class.build }

    it 'returns an MCP::Server instance' do
      expect(server).to be_a(MCP::Server)
    end

    it 'registers the correct name' do
      expect(server.name).to eq('legion')
    end

    it 'registers the correct version' do
      expect(server.version).to eq(Legion::VERSION)
    end

    it 'registers all tool classes' do
      expected = %w[
        legion.run_task legion.describe_runner
        legion.list_tasks legion.get_task legion.delete_task legion.get_task_logs
        legion.list_chains legion.create_chain legion.update_chain legion.delete_chain
        legion.list_relationships legion.create_relationship legion.update_relationship legion.delete_relationship
        legion.list_extensions legion.get_extension legion.enable_extension legion.disable_extension
        legion.list_schedules legion.create_schedule legion.update_schedule legion.delete_schedule
        legion.get_status legion.get_config
      ]
      expect(server.tools.keys).to include(*expected)
    end

    it 'registers exactly 30 tools' do
      expect(server.tools.size).to eq(30)
    end

    it 'includes instructions' do
      expect(server.instructions).to include('async job engine')
    end
  end
end
