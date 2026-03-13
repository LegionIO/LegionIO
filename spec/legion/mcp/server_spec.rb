# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do
  describe '.build' do
    subject(:server) { described_class.build }

    it 'returns an MCP::Server instance' do
      expect(server).to be_a(::MCP::Server)
    end

    it 'registers the correct name' do
      expect(server.name).to eq('legion')
    end

    it 'registers the correct version' do
      expect(server.version).to eq(Legion::VERSION)
    end

    it 'registers all tool classes' do
      tool_names = server.tools.keys
      expect(tool_names).to include('legion.run_task')
      expect(tool_names).to include('legion.describe_runner')
      expect(tool_names).to include('legion.list_tasks')
      expect(tool_names).to include('legion.get_task')
      expect(tool_names).to include('legion.delete_task')
      expect(tool_names).to include('legion.get_task_logs')
      expect(tool_names).to include('legion.list_chains')
      expect(tool_names).to include('legion.create_chain')
      expect(tool_names).to include('legion.update_chain')
      expect(tool_names).to include('legion.delete_chain')
      expect(tool_names).to include('legion.list_relationships')
      expect(tool_names).to include('legion.create_relationship')
      expect(tool_names).to include('legion.update_relationship')
      expect(tool_names).to include('legion.delete_relationship')
      expect(tool_names).to include('legion.list_extensions')
      expect(tool_names).to include('legion.get_extension')
      expect(tool_names).to include('legion.enable_extension')
      expect(tool_names).to include('legion.disable_extension')
      expect(tool_names).to include('legion.list_schedules')
      expect(tool_names).to include('legion.create_schedule')
      expect(tool_names).to include('legion.update_schedule')
      expect(tool_names).to include('legion.delete_schedule')
      expect(tool_names).to include('legion.get_status')
      expect(tool_names).to include('legion.get_config')
    end

    it 'registers exactly 24 tools' do
      expect(server.tools.size).to eq(24)
    end

    it 'includes instructions' do
      expect(server.instructions).to include('async job engine')
    end
  end
end
