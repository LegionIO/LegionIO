# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/summarize_traces'

RSpec.describe Legion::CLI::Chat::Tools::SummarizeTraces do
  subject(:tool) { described_class.new }

  describe '#execute' do
    before do
      stub_const('Legion::TraceSearch', Module.new)
      allow(tool).to receive(:require).with('legion/trace_search').and_return(true)
    end

    it 'returns formatted summary' do
      allow(Legion::TraceSearch).to receive(:summarize).and_return({
                                                                     total_records:    150,
                                                                     total_tokens_in:  45_000,
                                                                     total_tokens_out: 12_000,
                                                                     total_cost:       3.4567,
                                                                     avg_latency_ms:   245.3,
                                                                     max_latency_ms:   1200,
                                                                     time_range:       { from: '2026-03-22', to: '2026-03-23' },
                                                                     status_counts:    { 'success' => 140, 'failure' => 10 },
                                                                     top_extensions:   [{ name: 'lex-llm-gateway', count: 80 }],
                                                                     top_workers:      [{ id: 'worker-1', count: 60 }]
                                                                   })

      result = tool.execute(query: 'all tasks today')
      expect(result).to include('150 records')
      expect(result).to include('45000 in / 12000 out')
      expect(result).to include('$3.4567')
      expect(result).to include('avg 245.3ms')
      expect(result).to include('success: 140')
      expect(result).to include('lex-llm-gateway (80)')
      expect(result).to include('worker-1 (60)')
    end

    it 'returns error when filter generation fails' do
      allow(Legion::TraceSearch).to receive(:summarize).and_return({ error: 'no filter generated' })

      result = tool.execute(query: 'gibberish')
      expect(result).to include('Error: no filter generated')
    end

    it 'handles missing time range' do
      allow(Legion::TraceSearch).to receive(:summarize).and_return({
                                                                     total_records:    0,
                                                                     total_tokens_in:  0,
                                                                     total_tokens_out: 0,
                                                                     total_cost:       0,
                                                                     avg_latency_ms:   0,
                                                                     max_latency_ms:   0,
                                                                     time_range:       {},
                                                                     status_counts:    {},
                                                                     top_extensions:   [],
                                                                     top_workers:      []
                                                                   })

      result = tool.execute(query: 'empty query')
      expect(result).to include('0 records')
      expect(result).not_to include('Time range')
      expect(result).not_to include('Status')
      expect(result).not_to include('Top Extensions')
    end

    it 'handles LoadError when trace_search unavailable' do
      hide_const('Legion::TraceSearch')
      allow(tool).to receive(:require).with('legion/trace_search').and_raise(LoadError)

      result = tool.execute(query: 'test')
      expect(result).to include('Trace search unavailable')
    end

    it 'handles unexpected errors' do
      allow(Legion::TraceSearch).to receive(:summarize).and_raise(StandardError, 'db timeout')

      result = tool.execute(query: 'test')
      expect(result).to include('Error summarizing traces: db timeout')
    end
  end
end
