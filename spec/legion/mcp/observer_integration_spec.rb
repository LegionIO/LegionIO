# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do
  before(:each) { Legion::MCP::Observer.reset! }

  describe '.wire_observer' do
    context 'when method is tools/call with a tool_name' do
      let(:data) do
        {
          method:         'tools/call',
          tool_name:      'legion.run_task',
          tool_arguments: { task: 'http.request.get', params: {} },
          duration:       0.123,
          error:          nil,
          client:         nil
        }
      end

      it 'calls Observer.record for tools/call events' do
        expect(Legion::MCP::Observer).to receive(:record).with(
          tool_name:   'legion.run_task',
          duration_ms: 123,
          success:     true,
          params_keys: %i[task params],
          error:       nil
        )
        described_class.wire_observer(data)
      end

      it 'records an entry in the observer' do
        described_class.wire_observer(data)
        stats = Legion::MCP::Observer.tool_stats('legion.run_task')
        expect(stats[:call_count]).to eq(1)
      end

      it 'converts duration float (seconds) to integer milliseconds' do
        described_class.wire_observer(data)
        entry = Legion::MCP::Observer.recent(1).last
        expect(entry[:duration_ms]).to eq(123)
      end

      it 'extracts param keys from tool_arguments' do
        described_class.wire_observer(data)
        entry = Legion::MCP::Observer.recent(1).last
        expect(entry[:params_keys]).to contain_exactly(:task, :params)
      end

      it 'marks success true when error is nil' do
        described_class.wire_observer(data)
        entry = Legion::MCP::Observer.recent(1).last
        expect(entry[:success]).to be true
      end
    end

    context 'when error is present' do
      let(:data) do
        {
          method:         'tools/call',
          tool_name:      'legion.run_task',
          tool_arguments: {},
          duration:       0.05,
          error:          'Something went wrong',
          client:         nil
        }
      end

      it 'records failure when error is present' do
        described_class.wire_observer(data)
        stats = Legion::MCP::Observer.tool_stats('legion.run_task')
        expect(stats[:failure_count]).to eq(1)
      end

      it 'marks success false when error is present' do
        described_class.wire_observer(data)
        entry = Legion::MCP::Observer.recent(1).last
        expect(entry[:success]).to be false
      end
    end

    context 'when method is not tools/call' do
      let(:data) do
        {
          method:         'tools/list',
          tool_name:      nil,
          tool_arguments: {},
          duration:       0.001,
          error:          nil,
          client:         nil
        }
      end

      it 'ignores non-tools/call methods' do
        described_class.wire_observer(data)
        expect(Legion::MCP::Observer.all_tool_stats).to be_empty
      end
    end

    context 'when tool_name is nil' do
      let(:data) do
        {
          method:         'tools/call',
          tool_name:      nil,
          tool_arguments: {},
          duration:       0.001,
          error:          nil,
          client:         nil
        }
      end

      it 'ignores calls without a tool_name' do
        described_class.wire_observer(data)
        expect(Legion::MCP::Observer.all_tool_stats).to be_empty
      end
    end

    context 'with non-hash tool_arguments' do
      let(:data) do
        {
          method:         'tools/call',
          tool_name:      'legion.get_status',
          tool_arguments: nil,
          duration:       0.01,
          error:          nil,
          client:         nil
        }
      end

      it 'uses empty array for params_keys when tool_arguments has no keys' do
        described_class.wire_observer(data)
        entry = Legion::MCP::Observer.recent(1).last
        expect(entry[:params_keys]).to eq([])
      end
    end

    it 'rounds fractional milliseconds down to integer' do
      data = {
        method:         'tools/call',
        tool_name:      'legion.list_tasks',
        tool_arguments: {},
        duration:       0.0019,
        error:          nil,
        client:         nil
      }
      described_class.wire_observer(data)
      entry = Legion::MCP::Observer.recent(1).last
      expect(entry[:duration_ms]).to eq(1)
    end
  end
end
