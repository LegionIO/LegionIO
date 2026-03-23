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
end
