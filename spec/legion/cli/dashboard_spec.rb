# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/dashboard/renderer'
require 'legion/cli/dashboard/data_fetcher'

RSpec.describe Legion::CLI::Dashboard::Renderer do
  subject(:renderer) { described_class.new(width: 60) }

  let(:full_data) do
    {
      workers:     [
        { worker_id: 'w-alpha', status: 'active' },
        { worker_id: 'w-beta',  status: 'paused' }
      ],
      events:      [
        { timestamp: '2026-03-23T14:30:00Z', event_name: 'task.completed' },
        { timestamp: '2026-03-23T14:31:00Z', event_name: 'worker.started' }
      ],
      health:      { transport: 'ok', data: 'ok', cache: 'degraded' },
      departments: [
        { name: 'Engineering', roles: [
          { name: 'Developer', workers: [{ name: 'w-alpha', status: 'active' }] }
        ] }
      ],
      fetched_at:  Time.new(2026, 3, 23, 14, 32, 0)
    }
  end

  describe '#render' do
    it 'returns a string' do
      output = renderer.render(full_data)
      expect(output).to be_a(String)
    end

    it 'includes header with worker count' do
      output = renderer.render(full_data)
      expect(output).to include('Workers: 2')
    end

    it 'includes worker section' do
      output = renderer.render(full_data)
      expect(output).to include('w-alpha')
      expect(output).to include('active')
    end

    it 'includes events section' do
      output = renderer.render(full_data)
      expect(output).to include('task.completed')
    end

    it 'includes health section' do
      output = renderer.render(full_data)
      expect(output).to include('transport: ok')
      expect(output).to include('cache: degraded')
    end

    it 'includes org chart section' do
      output = renderer.render(full_data)
      expect(output).to include('Engineering')
      expect(output).to include('Developer')
    end

    it 'includes footer with timestamp' do
      output = renderer.render(full_data)
      expect(output).to include('14:32:00')
    end

    it 'handles empty data gracefully' do
      output = renderer.render({})
      expect(output).to include('(none)')
      expect(output).to include('(no departments)')
    end

    it 'uses separator lines' do
      output = renderer.render(full_data)
      expect(output).to include('-' * 60)
    end
  end
end

RSpec.describe Legion::CLI::Dashboard::DataFetcher do
  subject(:fetcher) { described_class.new(base_url: 'http://localhost:9999') }

  let(:mock_response) do
    r = instance_double(Net::HTTPOK)
    allow(r).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(r).to receive(:body).and_return(Legion::JSON.dump([{ id: 1 }]))
    r
  end

  describe '#workers' do
    it 'fetches from /api/workers' do
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      result = fetcher.workers
      expect(result).to be_an(Array)
    end

    it 'returns empty array on failure' do
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      expect(fetcher.workers).to eq([])
    end
  end

  describe '#health' do
    it 'fetches from /api/health' do
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      result = fetcher.health
      expect(result).not_to be_nil
    end

    it 'returns empty hash on failure' do
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      expect(fetcher.health).to eq({})
    end
  end

  describe '#recent_events' do
    it 'returns empty array on failure' do
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      expect(fetcher.recent_events).to eq([])
    end
  end

  describe '#summary' do
    it 'aggregates workers, health, and events' do
      allow(Net::HTTP).to receive(:get_response).and_raise(Errno::ECONNREFUSED)
      result = fetcher.summary
      expect(result).to have_key(:workers)
      expect(result).to have_key(:health)
      expect(result).to have_key(:events)
      expect(result).to have_key(:fetched_at)
      expect(result[:fetched_at]).to be_a(Time)
    end
  end
end
