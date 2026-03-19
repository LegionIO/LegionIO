# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'

RSpec.describe Legion::MCP::Observer do
  before(:each) { described_class.reset! }

  # ---------------------------------------------------------------------------
  # reset! / started_at
  # ---------------------------------------------------------------------------
  describe '.reset!' do
    it 'clears all counters' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.reset!
      expect(described_class.all_tool_stats).to be_empty
    end

    it 'clears the ring buffer' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.reset!
      expect(described_class.recent(100)).to be_empty
    end

    it 'clears the intent buffer' do
      described_class.record_intent('list tasks', 'legion.list_tasks')
      described_class.reset!
      expect(described_class.recent_intents(100)).to be_empty
    end

    it 'resets started_at to approximately now' do
      before_reset = Time.now
      described_class.reset!
      expect(described_class.started_at).to be >= before_reset
    end
  end

  # ---------------------------------------------------------------------------
  # record
  # ---------------------------------------------------------------------------
  describe '.record' do
    it 'increments call_count for a new tool' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 50, success: true)
      expect(described_class.tool_stats('legion.run_task')[:call_count]).to eq(1)
    end

    it 'accumulates call_count across multiple calls' do
      3.times { described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true) }
      expect(described_class.tool_stats('legion.run_task')[:call_count]).to eq(3)
    end

    it 'increments failure_count on failure' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: false, error: 'boom')
      expect(described_class.tool_stats('legion.run_task')[:failure_count]).to eq(1)
    end

    it 'does not increment failure_count on success' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      expect(described_class.tool_stats('legion.run_task')[:failure_count]).to eq(0)
    end

    it 'stores the last error message on failure' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: false, error: 'timeout')
      expect(described_class.tool_stats('legion.run_task')[:last_error]).to eq('timeout')
    end

    it 'does not overwrite last_error on subsequent successes' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: false, error: 'first_error')
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      expect(described_class.tool_stats('legion.run_task')[:last_error]).to eq('first_error')
    end

    it 'updates last_used timestamp' do
      before = Time.now
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      expect(described_class.tool_stats('legion.run_task')[:last_used]).to be >= before
    end

    it 'appends an entry to the ring buffer' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 25, success: true,
                             params_keys: [:task])
      entry = described_class.recent(1).last
      expect(entry[:tool_name]).to eq('legion.run_task')
      expect(entry[:duration_ms]).to eq(25)
      expect(entry[:success]).to be true
      expect(entry[:params_keys]).to eq([:task])
    end

    it 'enforces ring buffer max of 500' do
      501.times { |i| described_class.record(tool_name: "tool_#{i}", duration_ms: 1, success: true) }
      expect(described_class.recent(1000).size).to eq(500)
    end

    it 'drops the oldest entry when ring buffer overflows' do
      501.times { |i| described_class.record(tool_name: "tool_#{i}", duration_ms: 1, success: true) }
      oldest = described_class.recent(500).first[:tool_name]
      expect(oldest).to eq('tool_1')
    end

    it 'tracks multiple different tools independently' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)
      expect(described_class.tool_stats('legion.run_task')[:call_count]).to eq(1)
      expect(described_class.tool_stats('legion.list_tasks')[:call_count]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # record_intent
  # ---------------------------------------------------------------------------
  describe '.record_intent' do
    it 'appends to the intent buffer' do
      described_class.record_intent('list all running tasks', 'legion.list_tasks')
      entry = described_class.recent_intents(1).last
      expect(entry[:intent]).to eq('list all running tasks')
      expect(entry[:matched_tool]).to eq('legion.list_tasks')
    end

    it 'enforces intent buffer max of 200' do
      201.times { |i| described_class.record_intent("intent #{i}", 'legion.list_tasks') }
      expect(described_class.recent_intents(1000).size).to eq(200)
    end

    it 'drops the oldest intent when buffer overflows' do
      201.times { |i| described_class.record_intent("intent #{i}", 'legion.list_tasks') }
      oldest = described_class.recent_intents(200).first[:intent]
      expect(oldest).to eq('intent 1')
    end

    it 'records a timestamp' do
      before = Time.now
      described_class.record_intent('run something', 'legion.run_task')
      expect(described_class.recent_intents(1).last[:recorded_at]).to be >= before
    end
  end

  # ---------------------------------------------------------------------------
  # tool_stats
  # ---------------------------------------------------------------------------
  describe '.tool_stats' do
    it 'returns nil for an unknown tool' do
      expect(described_class.tool_stats('no.such.tool')).to be_nil
    end

    it 'returns correct avg_latency_ms' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 100, success: true)
      described_class.record(tool_name: 'legion.run_task', duration_ms: 200, success: true)
      expect(described_class.tool_stats('legion.run_task')[:avg_latency_ms]).to eq(150.0)
    end

    it 'returns 0.0 avg_latency_ms when call_count is zero (guarded path via direct counters)' do
      # Manipulate counters directly to simulate a zero-count edge case
      described_class.counters['ghost_tool'] = {
        call_count: 0, total_latency_ms: 0.0, failure_count: 0, last_used: nil, last_error: nil
      }
      expect(described_class.tool_stats('ghost_tool')[:avg_latency_ms]).to eq(0.0)
    end

    it 'returns the correct name key' do
      described_class.record(tool_name: 'legion.get_status', duration_ms: 5, success: true)
      expect(described_class.tool_stats('legion.get_status')[:name]).to eq('legion.get_status')
    end

    it 'includes last_used' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      expect(described_class.tool_stats('legion.run_task')[:last_used]).to be_a(Time)
    end
  end

  # ---------------------------------------------------------------------------
  # all_tool_stats
  # ---------------------------------------------------------------------------
  describe '.all_tool_stats' do
    it 'returns an empty hash when no tools recorded' do
      expect(described_class.all_tool_stats).to eq({})
    end

    it 'returns a hash keyed by tool name' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)
      result = described_class.all_tool_stats
      expect(result.keys).to contain_exactly('legion.run_task', 'legion.list_tasks')
    end

    it 'each value matches tool_stats output' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 20, success: true)
      result = described_class.all_tool_stats
      expect(result['legion.run_task']).to eq(described_class.tool_stats('legion.run_task'))
    end
  end

  # ---------------------------------------------------------------------------
  # stats
  # ---------------------------------------------------------------------------
  describe '.stats' do
    it 'returns zero totals when nothing recorded' do
      result = described_class.stats
      expect(result[:total_calls]).to eq(0)
      expect(result[:tool_count]).to eq(0)
      expect(result[:failure_rate]).to eq(0.0)
      expect(result[:top_tools]).to eq([])
    end

    it 'counts total calls across all tools' do
      3.times { described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true) }
      2.times { described_class.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true) }
      expect(described_class.stats[:total_calls]).to eq(5)
    end

    it 'counts distinct tools' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)
      expect(described_class.stats[:tool_count]).to eq(2)
    end

    it 'calculates failure_rate correctly' do
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: false)
      expect(described_class.stats[:failure_rate]).to eq(0.5)
    end

    it 'returns top_tools sorted by call_count descending' do
      5.times { described_class.record(tool_name: 'legion.run_task', duration_ms: 10, success: true) }
      2.times { described_class.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true) }
      top = described_class.stats[:top_tools]
      expect(top.first[:name]).to eq('legion.run_task')
      expect(top.last[:name]).to eq('legion.list_tasks')
    end

    it 'returns at most 10 tools in top_tools' do
      15.times { |i| described_class.record(tool_name: "legion.tool_#{i}", duration_ms: i, success: true) }
      expect(described_class.stats[:top_tools].size).to eq(10)
    end

    it 'includes the since timestamp' do
      expect(described_class.stats[:since]).to be_a(Time)
    end
  end

  # ---------------------------------------------------------------------------
  # recent
  # ---------------------------------------------------------------------------
  describe '.recent' do
    it 'returns an empty array when nothing recorded' do
      expect(described_class.recent(10)).to eq([])
    end

    it 'returns the last N entries in chronological order' do
      5.times { |i| described_class.record(tool_name: "tool_#{i}", duration_ms: i, success: true) }
      result = described_class.recent(3)
      expect(result.size).to eq(3)
      expect(result.map { |e| e[:tool_name] }).to eq(%w[tool_2 tool_3 tool_4])
    end

    it 'returns all entries if limit exceeds buffer size' do
      2.times { |i| described_class.record(tool_name: "tool_#{i}", duration_ms: i, success: true) }
      expect(described_class.recent(100).size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # recent_intents
  # ---------------------------------------------------------------------------
  describe '.recent_intents' do
    it 'returns an empty array when nothing recorded' do
      expect(described_class.recent_intents(10)).to eq([])
    end

    it 'returns the last N intents in chronological order' do
      5.times { |i| described_class.record_intent("intent #{i}", 'legion.list_tasks') }
      result = described_class.recent_intents(3)
      expect(result.size).to eq(3)
      expect(result.map { |e| e[:intent] }).to eq(['intent 2', 'intent 3', 'intent 4'])
    end

    it 'returns all intents if limit exceeds buffer size' do
      2.times { |i| described_class.record_intent("intent #{i}", 'legion.list_tasks') }
      expect(described_class.recent_intents(100).size).to eq(2)
    end
  end
end
