# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/manage_tasks'

RSpec.describe Legion::CLI::Chat::Tools::ManageTasks do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'invalid action' do
      it 'returns error for unknown action' do
        result = tool.execute(action: 'destroy')
        expect(result).to include('Invalid action: destroy')
        expect(result).to include('list, show, logs, trigger')
      end
    end

    context 'list action' do
      it 'returns formatted task list' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({
                          data: [
                            { id: 1, status: 'completed', runner_class: 'Node::Runners::Info',
                              function: 'execute', created_at: '2026-03-23T10:00:00Z' },
                            { id: 2, status: 'failed', runner_class: 'Scheduler::Runners::Run',
                              function: 'trigger', created_at: '2026-03-23T10:05:00Z' }
                          ]
                        })
        )
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute(action: 'list')
        expect(result).to include('Recent Tasks (2)')
        expect(result).to include('#1 [completed]')
        expect(result).to include('#2 [failed]')
        expect(result).to include('Node::Runners::Info')
      end

      it 'passes status filter' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
        expect(mock_http).to receive(:get) do |uri|
          expect(uri).to include('status=failed')
          response
        end

        tool.execute(action: 'list', status: 'failed')
      end

      it 'returns message when no tasks found' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute(action: 'list')
        expect(result).to include('No tasks found')
      end
    end

    context 'show action' do
      it 'returns task detail with metering' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({
                          data: {
                            id: 42, status: 'completed',
                            runner_class: 'Node::Runners::Info', function: 'execute',
                            created_at: '2026-03-23T10:00:00Z', updated_at: '2026-03-23T10:00:05Z',
                            metering: {
                              total_tokens: 1500, input_tokens: 1000, output_tokens: 500,
                              total_calls: 3, avg_latency_ms: 120.5,
                              provider: ['bedrock'], model: ['claude-sonnet-4-20250514']
                            }
                          }
                        })
        )
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute(action: 'show', task_id: 42)
        expect(result).to include('Task #42')
        expect(result).to include('Status: completed')
        expect(result).to include('Metering:')
        expect(result).to include('Total tokens: 1500')
        expect(result).to include('Avg latency: 120.5ms')
      end

      it 'requires task_id' do
        result = tool.execute(action: 'show')
        expect(result).to include('task_id is required')
      end
    end

    context 'logs action' do
      it 'returns formatted task logs' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({
                          data: [
                            { created_at: '2026-03-23T10:00:00Z', level: 'info', message: 'Task started' },
                            { created_at: '2026-03-23T10:00:05Z', level: 'info', message: 'Task completed' }
                          ]
                        })
        )
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute(action: 'logs', task_id: 42)
        expect(result).to include('Logs for Task #42 (2 entries)')
        expect(result).to include('Task started')
        expect(result).to include('Task completed')
      end

      it 'requires task_id' do
        result = tool.execute(action: 'logs')
        expect(result).to include('task_id is required')
      end

      it 'handles empty logs' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute(action: 'logs', task_id: 99)
        expect(result).to include('No logs found for task 99')
      end
    end

    context 'trigger action' do
      it 'triggers a task via POST' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({ data: { task_id: 100 } })
        )

        request = instance_double(Net::HTTP::Post)
        allow(request).to receive(:body=)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(mock_http).to receive(:request).and_return(response)

        result = tool.execute(action: 'trigger', runner_class: 'Node::Runners::Info', function: 'execute')
        expect(result).to include('Task triggered successfully')
        expect(result).to include('Task ID: 100')
      end

      it 'requires runner_class' do
        result = tool.execute(action: 'trigger', function: 'execute')
        expect(result).to include('runner_class is required')
      end

      it 'requires function' do
        result = tool.execute(action: 'trigger', runner_class: 'Node::Runners::Info')
        expect(result).to include('function is required')
      end

      it 'passes JSON payload' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({ data: { task_id: 101 } })
        )

        request = instance_double(Net::HTTP::Post)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(mock_http).to receive(:request).and_return(response)

        expect(request).to receive(:body=) do |body|
          parsed = JSON.parse(body, symbolize_names: true)
          expect(parsed[:runner_class]).to eq('Node::Runners::Info')
          expect(parsed[:target]).to eq('localhost')
        end

        tool.execute(action: 'trigger', runner_class: 'Node::Runners::Info',
                     function: 'execute', payload: '{"target":"localhost"}')
      end
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      result = tool.execute(action: 'list')
      expect(result).to include('daemon not running')
    end

    it 'handles API error response' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ error: 'service unavailable' }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(action: 'list')
      expect(result).to include('API error: service unavailable')
    end
  end
end
