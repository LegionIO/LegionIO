# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/view_events'

RSpec.describe Legion::CLI::Chat::Tools::ViewEvents do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'returns formatted event list' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({
                        data: [
                          { event: 'runner.completed', timestamp: '2026-03-23T10:00:00Z',
                            extension: 'lex-node', status: 'success' },
                          { event: 'worker.lifecycle', timestamp: '2026-03-23T10:01:00Z',
                            worker_id: 'w-1', status: 'active' }
                        ]
                      })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Recent Events (2)')
      expect(result).to include('runner.completed')
      expect(result).to include('extension: lex-node')
      expect(result).to include('worker.lifecycle')
      expect(result).to include('worker_id: w-1')
    end

    it 'returns no events message when empty' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('No recent events')
    end

    it 'passes count parameter' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
      expect(mock_http).to receive(:get) do |uri|
        expect(uri).to include('count=5')
        response
      end

      tool.execute(count: 5)
    end

    it 'clamps count to valid range' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
      expect(mock_http).to receive(:get) do |uri|
        expect(uri).to include('count=100')
        response
      end

      tool.execute(count: 999)
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      result = tool.execute
      expect(result).to include('daemon not running')
    end

    it 'handles API error response' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ error: 'events unavailable' }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('API error: events unavailable')
    end

    it 'handles events without details' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({
                        data: [{ event: 'service.ready', timestamp: '2026-03-23T10:00:00Z' }]
                      })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('service.ready')
      expect(result).not_to include('—')
    end
  end
end
