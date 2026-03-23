# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/view_trends'

RSpec.describe Legion::CLI::Chat::Tools::ViewTrends do
  subject(:tool) { described_class.new }

  before { allow(tool).to receive(:api_port).and_return(4567) }

  describe '#execute' do
    it 'formats trend data as a table' do
      stub_trend(
        buckets: [
          { time: '2026-03-23T00:00:00Z', count: 100, avg_cost: 0.05, avg_latency: 150.0, failure_rate: 0.02 },
          { time: '2026-03-23T02:00:00Z', count: 120, avg_cost: 0.06, avg_latency: 160.0, failure_rate: 0.01 }
        ],
        hours: 4, bucket_minutes: 120
      )

      result = tool.execute(hours: 4, buckets: 2)
      expect(result).to include('Trend (last 4h')
      expect(result).to include('Count')
      expect(result).to include('Avg Cost')
      expect(result).to include('Direction:')
    end

    it 'shows rising trend when second half increases' do
      stub_trend(
        buckets: [
          { time: '2026-03-23T00:00:00Z', count: 10, avg_cost: 0.01, avg_latency: 100.0, failure_rate: 0.0 },
          { time: '2026-03-23T12:00:00Z', count: 50, avg_cost: 0.10, avg_latency: 200.0, failure_rate: 0.1 }
        ],
        hours: 24, bucket_minutes: 720
      )

      result = tool.execute
      expect(result).to include('rising')
    end

    it 'shows stable trend when metrics are consistent' do
      bucket = { time: '2026-03-23T00:00:00Z', count: 50, avg_cost: 0.05, avg_latency: 100.0, failure_rate: 0.01 }
      stub_trend(
        buckets: [bucket, bucket.merge(time: '2026-03-23T12:00:00Z')],
        hours: 24, bucket_minutes: 720
      )

      result = tool.execute
      expect(result).to include('stable')
    end

    it 'handles empty trend data' do
      stub_trend(buckets: [], hours: 24, bucket_minutes: 120)

      result = tool.execute
      expect(result).to include('No trend data available')
    end

    it 'handles connection refused' do
      allow(tool).to receive(:api_get).and_raise(Errno::ECONNREFUSED)

      result = tool.execute
      expect(result).to include('Legion daemon not running')
    end

    it 'handles API error response' do
      allow(tool).to receive(:api_get).and_return({ error: { message: 'LLM unavailable' } })

      result = tool.execute
      expect(result).to include('LLM unavailable')
    end
  end

  def stub_trend(data)
    allow(tool).to receive(:api_get).and_return({ data: data })
  end
end
