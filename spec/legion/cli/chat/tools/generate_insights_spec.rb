# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/generate_insights'

RSpec.describe Legion::CLI::Chat::Tools::GenerateInsights do
  subject(:tool) { described_class.new }

  before { allow(tool).to receive(:api_port).and_return(4567) }

  describe '#execute' do
    it 'generates a comprehensive report' do
      stub_all_endpoints
      result = tool.execute
      expect(result).to include('System Insights Report')
      expect(result).to include('Health: ok')
      expect(result).to include('Anomalies: None detected')
      expect(result).to include('Knowledge: 500 entries')
    end

    it 'includes anomaly details when present' do
      stub_all_endpoints(
        anomalies: { data: { anomalies: [{ metric: 'Average cost', ratio: 5.0, severity: 'critical' }] } }
      )
      result = tool.execute
      expect(result).to include('[CRITICAL] Average cost')
    end

    it 'shows trend direction' do
      stub_all_endpoints
      result = tool.execute
      expect(result).to include('Trend (24h)')
    end

    it 'generates recommendations for anomalies' do
      stub_all_endpoints(
        anomalies: { data: { anomalies: [{ metric: 'Average cost', ratio: 3.0, severity: 'warning' }] } }
      )
      result = tool.execute
      expect(result).to include('Recommendations')
      expect(result).to include('model downgrade')
    end

    it 'handles daemon not running' do
      allow(tool).to receive(:safe_fetch).and_return(nil)
      result = tool.execute
      expect(result).to include('daemon not running')
    end

    it 'handles connection refused' do
      allow(tool).to receive(:gather_sections).and_raise(Errno::ECONNREFUSED)
      result = tool.execute
      expect(result).to include('daemon not running')
    end

    it 'handles partial data gracefully' do
      allow(tool).to receive(:safe_fetch).and_return(nil)
      allow(tool).to receive(:safe_fetch).with('/api/health').and_return({ data: { status: 'ok' } })
      result = tool.execute
      expect(result).to include('Health: ok')
    end
  end

  def stub_all_endpoints(overrides = {})
    defaults = {
      health:    { data: { status: 'ok', version: '1.4.167' } },
      anomalies: { data: { anomalies: [], recent_count: 50, baseline_count: 500 } },
      trend:     { data: { buckets: [
        { time: '2026-03-22T00:00:00Z', count: 100, avg_cost: 0.05, avg_latency: 100.0, failure_rate: 0.01 },
        { time: '2026-03-23T00:00:00Z', count: 120, avg_cost: 0.06, avg_latency: 110.0, failure_rate: 0.02 }
      ], hours: 24, bucket_count: 6 } },
      apollo:    { data: { total_entries: 500, recent_24h: 20, avg_confidence: 0.85 } },
      workers:   { data: [{ lifecycle_state: 'active' }, { lifecycle_state: 'paused' }] }
    }.merge(overrides)

    allow(tool).to receive(:safe_fetch).with('/api/health').and_return(defaults[:health])
    allow(tool).to receive(:safe_fetch).with('/api/traces/anomalies').and_return(defaults[:anomalies])
    allow(tool).to receive(:safe_fetch).with('/api/traces/trend?hours=24&buckets=6').and_return(defaults[:trend])
    allow(tool).to receive(:safe_fetch).with('/api/apollo/stats').and_return(defaults[:apollo])
    allow(tool).to receive(:safe_fetch).with('/api/workers').and_return(defaults[:workers])
  end
end
