# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/trace_command'

RSpec.describe Legion::CLI::TraceCommand do
  let(:search_result) do
    {
      results:   [
        { created_at: Time.utc(2026, 3, 23, 12, 0, 0), extension: 'lex-llm-gateway',
          runner_function: 'route_request', status: 'success', cost_usd: 0.0042,
          tokens_in: 120, tokens_out: 350, wall_clock_ms: 1200, worker_id: 'w-1' },
        { created_at: Time.utc(2026, 3, 23, 11, 30, 0), extension: 'lex-apollo',
          runner_function: 'ingest', status: 'failure', cost_usd: 0.0,
          tokens_in: 0, tokens_out: 0, wall_clock_ms: 50, worker_id: nil }
      ],
      count:     2,
      total:     5,
      truncated: true,
      filter:    { where: { status: 'success' } }
    }
  end

  before do
    stub_const('Legion::TraceSearch', Module.new)
    allow(Legion::TraceSearch).to receive(:search).and_return(search_result)

    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_llm)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  describe '#search' do
    it 'outputs Trace Search header' do
      expect { described_class.start(%w[search failed tasks --no-color]) }.to output(/Trace Search/).to_stdout
    end

    it 'shows query text' do
      expect { described_class.start(%w[search failed tasks --no-color]) }.to output(/failed tasks/).to_stdout
    end

    it 'shows result count and total' do
      expect { described_class.start(%w[search failed tasks --no-color]) }.to output(/2 of 5 results/).to_stdout
    end

    it 'indicates truncation' do
      expect { described_class.start(%w[search failed tasks --no-color]) }.to output(/truncated/).to_stdout
    end

    it 'shows extension and function' do
      expect { described_class.start(%w[search all --no-color]) }.to output(/lex-llm-gateway\.route_request/).to_stdout
    end

    it 'shows cost' do
      expect { described_class.start(%w[search all --no-color]) }.to output(/\$0\.0042/).to_stdout
    end

    it 'shows tokens' do
      expect { described_class.start(%w[search all --no-color]) }.to output(%r{120in/350out}).to_stdout
    end

    it 'shows wall clock time' do
      expect { described_class.start(%w[search all --no-color]) }.to output(/1200ms/).to_stdout
    end

    it 'shows worker id when present' do
      expect { described_class.start(%w[search all --no-color]) }.to output(/worker: w-1/).to_stdout
    end

    context 'with --json flag' do
      it 'outputs JSON' do
        expect { described_class.start(%w[search all --json --no-color]) }.to output(/results/).to_stdout
      end
    end

    context 'when search returns error' do
      before do
        allow(Legion::TraceSearch).to receive(:search).and_return({ results: [], error: 'data unavailable' })
      end

      it 'displays error message' do
        expect { described_class.start(%w[search all --no-color]) }.to output(/data unavailable/).to_stdout
      end
    end

    context 'when no results found' do
      before do
        allow(Legion::TraceSearch).to receive(:search).and_return({ results: [], count: 0, total: 0, truncated: false })
      end

      it 'shows no results message' do
        expect { described_class.start(%w[search all --no-color]) }.to output(/No results found/).to_stdout
      end
    end

    it 'passes limit option to TraceSearch' do
      described_class.start(%w[search expensive --limit 10 --no-color])
      expect(Legion::TraceSearch).to have_received(:search).with('expensive', limit: 10)
    end
  end

  describe '#summarize' do
    let(:summary_result) do
      {
        total_records:    100,
        total_tokens_in:  5000,
        total_tokens_out: 8000,
        total_cost:       1.2345,
        avg_latency_ms:   150.7,
        max_latency_ms:   2500,
        time_range:       { from: Time.utc(2026, 3, 1), to: Time.utc(2026, 3, 23) },
        status_counts:    { 'success' => 90, 'failure' => 10 },
        top_extensions:   [{ name: 'http', count: 60 }, { name: 'vault', count: 40 }],
        top_workers:      [{ id: 'w-1', count: 70 }],
        filter:           {}
      }
    end

    before do
      allow(Legion::TraceSearch).to receive(:summarize).and_return(summary_result)
    end

    it 'outputs Trace Summary header' do
      expect { described_class.start(%w[summarize all tasks --no-color]) }.to output(/Trace Summary/).to_stdout
    end

    it 'shows total records' do
      expect { described_class.start(%w[summarize all --no-color]) }.to output(/100/).to_stdout
    end

    it 'shows total cost' do
      expect { described_class.start(%w[summarize all --no-color]) }.to output(/\$1\.2345/).to_stdout
    end

    it 'shows status breakdown' do
      expect { described_class.start(%w[summarize all --no-color]) }.to output(/success: 90/).to_stdout
    end

    it 'shows top extensions' do
      expect { described_class.start(%w[summarize all --no-color]) }.to output(/http: 60/).to_stdout
    end

    it 'shows top workers' do
      expect { described_class.start(%w[summarize all --no-color]) }.to output(/w-1: 70/).to_stdout
    end

    context 'with --json flag' do
      it 'outputs JSON' do
        expect { described_class.start(%w[summarize all --json --no-color]) }.to output(/total_records/).to_stdout
      end
    end

    context 'when summarize returns error' do
      before do
        allow(Legion::TraceSearch).to receive(:summarize).and_return({ error: 'data unavailable' })
      end

      it 'displays error message' do
        expect { described_class.start(%w[summarize all --no-color]) }.to output(/data unavailable/).to_stdout
      end
    end
  end
end
