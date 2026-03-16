# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/telemetry_command'

RSpec.describe Legion::CLI::Telemetry do
  let(:runner_stub) do
    Module.new do
      def self.aggregate_stats(**)
        { success: true, stats: { session_count: 3, total_events: 150, tool_frequency: { 'Read' => 50 } } }
      end

      def self.session_stats(session_id:, **)
        { success: true, stats: { session_id: session_id, tool_counts: { 'Read' => 5 }, error_count: 0 } }
      end

      def self.ingest_session(file_path:, **)
        { success: true, event_count: 10, session_id: 'abc-123', file_path: file_path }
      end

      def self.telemetry_status(**)
        { success: true, buffer_size: 100, pending_count: 5, session_count: 3, parsers: [:claude_code] }
      end
    end
  end

  before do
    stub_const('Legion::Extensions::Telemetry::Runners::Telemetry', runner_stub)
    allow_any_instance_of(described_class).to receive(:telemetry_runner).and_return(runner_stub)
  end

  describe '#stats' do
    it 'calls aggregate_stats when no session_id given' do
      expect { described_class.new.invoke(:stats) }.to output(/session_count/).to_stdout
    end

    it 'calls session_stats when session_id given' do
      expect { described_class.new.invoke(:stats, ['abc-123']) }.to output(/tool_counts/).to_stdout
    end
  end

  describe '#ingest' do
    it 'calls ingest_session with file path' do
      expect { described_class.new.invoke(:ingest, ['/tmp/test.jsonl']) }.to output(/Ingested.*10/).to_stdout
    end
  end

  describe '#status' do
    it 'calls telemetry_status' do
      expect { described_class.new.invoke(:status) }.to output(/Buffer Size/).to_stdout
    end
  end
end
