# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/detect_anomalies'

RSpec.describe Legion::CLI::Chat::Tools::DetectAnomalies do
  subject(:tool) { described_class.new }

  let(:api_port) { 4567 }

  before do
    allow(tool).to receive(:api_port).and_return(api_port)
  end

  describe '#execute' do
    it 'reports no anomalies when system is healthy' do
      stub_api_response(
        anomalies: [], recent_count: 50, baseline_count: 500,
        recent_period: 'last 1 hour', baseline_period: 'previous 23 hours'
      )

      result = tool.execute
      expect(result).to include('No anomalies detected')
      expect(result).to include('50 records')
    end

    it 'reports detected anomalies with severity' do
      stub_api_response(
        anomalies: [
          { metric: 'Average cost', recent: 0.5, baseline: 0.05, ratio: 10.0, severity: 'critical' },
          { metric: 'Average latency', recent: 500.0, baseline: 100.0, ratio: 5.0, severity: 'warning' }
        ],
        recent_count: 20, baseline_count: 300,
        recent_period: 'last 1 hour', baseline_period: 'previous 23 hours'
      )

      result = tool.execute
      expect(result).to include('2 anomalies detected')
      expect(result).to include('[CRITICAL] Average cost')
      expect(result).to include('[WARNING] Average latency')
      expect(result).to include('Ratio: 10.0x')
    end

    it 'passes custom threshold' do
      stub_api_response_for_threshold(3.5, anomalies: [], recent_count: 10, baseline_count: 100)

      result = tool.execute(threshold: 3.5)
      expect(result).to include('No anomalies detected')
    end

    it 'handles API error response' do
      stub_api_error('trace_search_unavailable', 'TraceSearch requires LLM subsystem')

      result = tool.execute
      expect(result).to include('TraceSearch requires LLM subsystem')
    end

    it 'handles connection refused' do
      allow(tool).to receive(:api_get).and_raise(Errno::ECONNREFUSED)

      result = tool.execute
      expect(result).to include('Legion daemon not running')
    end

    it 'handles single anomaly grammar' do
      stub_api_response(
        anomalies: [{ metric: 'Failure rate', recent: 0.4, baseline: 0.1, ratio: 4.0, severity: 'warning' }],
        recent_count: 15, baseline_count: 200
      )

      result = tool.execute
      expect(result).to include('1 anomaly detected')
    end
  end

  def stub_api_response(data)
    allow(tool).to receive(:api_get).and_return({ data: data })
  end

  def stub_api_response_for_threshold(threshold, data)
    allow(tool).to receive(:api_get)
      .with("/api/traces/anomalies?threshold=#{threshold}")
      .and_return({ data: data })
  end

  def stub_api_error(code, message)
    allow(tool).to receive(:api_get).and_return({ error: { code: code, message: message } })
  end
end
