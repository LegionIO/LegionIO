# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::UsageFilter do
  before(:each) { Legion::MCP::Observer.reset! }

  let(:tool_names) { %w[legion.run_task legion.list_tasks legion.get_status legion.describe_runner legion.delete_task] }

  # ---------------------------------------------------------------------------
  # score_tools
  # ---------------------------------------------------------------------------
  describe '.score_tools' do
    it 'returns a hash keyed by tool name' do
      result = described_class.score_tools(tool_names)
      expect(result).to be_a(Hash)
      expect(result.keys).to match_array(tool_names)
    end

    it 'returns numeric scores for all tools' do
      result = described_class.score_tools(tool_names)
      result.each_value { |score| expect(score).to be_a(Numeric) }
    end

    it 'gives a higher score to more frequently used tools' do
      10.times { Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 10, success: true) }
      Legion::MCP::Observer.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)

      scores = described_class.score_tools(%w[legion.run_task legion.list_tasks])
      expect(scores['legion.run_task']).to be > scores['legion.list_tasks']
    end

    it 'gives a higher score to recently used tools' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      # Manually set an old last_used for list_tasks by recording then faking the counter
      Legion::MCP::Observer.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)
      Legion::MCP::Observer.counters['legion.list_tasks'][:last_used] = Time.now - 80_000

      scores = described_class.score_tools(%w[legion.run_task legion.list_tasks])
      expect(scores['legion.run_task']).to be > scores['legion.list_tasks']
    end

    it 'returns baseline score for tools with no usage data' do
      scores = described_class.score_tools(['legion.delete_task'])
      expect(scores['legion.delete_task']).to eq(described_class::BASELINE_SCORE)
    end

    it 'boosts tools that match keywords' do
      scores_with    = described_class.score_tools(%w[legion.run_task legion.list_tasks], keywords: ['run'])
      scores_without = described_class.score_tools(%w[legion.run_task legion.list_tasks])

      expect(scores_with['legion.run_task']).to be > scores_without['legion.run_task']
    end

    it 'does not boost tools that do not match keywords' do
      scores_with    = described_class.score_tools(%w[legion.run_task legion.list_tasks], keywords: ['run'])
      scores_without = described_class.score_tools(%w[legion.run_task legion.list_tasks])

      expect(scores_with['legion.list_tasks']).to eq(scores_without['legion.list_tasks'])
    end
  end

  # ---------------------------------------------------------------------------
  # ranked_tools
  # ---------------------------------------------------------------------------
  describe '.ranked_tools' do
    it 'returns an array of tool names' do
      result = described_class.ranked_tools(tool_names)
      expect(result).to be_an(Array)
      expect(result).to match_array(tool_names)
    end

    it 'sorts by score descending (more calls = higher rank)' do
      5.times { Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 10, success: true) }
      Legion::MCP::Observer.record(tool_name: 'legion.list_tasks', duration_ms: 5, success: true)

      ranked = described_class.ranked_tools(%w[legion.run_task legion.list_tasks legion.get_status])
      expect(ranked.first).to eq('legion.run_task')
    end

    it 'respects the limit parameter' do
      result = described_class.ranked_tools(tool_names, limit: 2)
      expect(result.size).to eq(2)
    end

    it 'returns all tools when limit is nil' do
      result = described_class.ranked_tools(tool_names, limit: nil)
      expect(result.size).to eq(tool_names.size)
    end

    it 'boosts keyword-matching tools to higher rank' do
      ranked = described_class.ranked_tools(%w[legion.run_task legion.list_tasks], keywords: ['list'])
      expect(ranked.first).to eq('legion.list_tasks')
    end
  end

  # ---------------------------------------------------------------------------
  # prune_dead_tools
  # ---------------------------------------------------------------------------
  describe '.prune_dead_tools' do
    it 'keeps all tools when observation window has not exceeded threshold' do
      result = described_class.prune_dead_tools(tool_names, prune_after_seconds: 86_400 * 30)
      expect(result).to match_array(tool_names)
    end

    it 'removes tools with zero calls when threshold is exceeded' do
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)
      # Force started_at to be old enough to trigger pruning
      Legion::MCP::Observer.instance_variable_set(:@started_at, Time.now - (86_400 * 31))

      result = described_class.prune_dead_tools(
        %w[legion.run_task legion.delete_task],
        prune_after_seconds: 86_400 * 30
      )
      expect(result).to include('legion.run_task')
      expect(result).not_to include('legion.delete_task')
    end

    it 'never prunes essential tools even when threshold is exceeded and they have zero calls' do
      Legion::MCP::Observer.instance_variable_set(:@started_at, Time.now - (86_400 * 31))

      names_with_essential = %w[legion.run_task legion.get_status legion.delete_task]
      # Only run_task has calls; get_status and delete_task have zero
      Legion::MCP::Observer.record(tool_name: 'legion.run_task', duration_ms: 10, success: true)

      result = described_class.prune_dead_tools(names_with_essential, prune_after_seconds: 86_400 * 30)
      expect(result).to include('legion.get_status')
      expect(result).not_to include('legion.delete_task')
    end

    it 'keeps all tools before threshold regardless of call count' do
      Legion::MCP::Observer.instance_variable_set(:@started_at, Time.now - 100)

      result = described_class.prune_dead_tools(
        %w[legion.run_task legion.delete_task],
        prune_after_seconds: 86_400 * 30
      )
      expect(result).to match_array(%w[legion.run_task legion.delete_task])
    end
  end

  # ---------------------------------------------------------------------------
  # recency_decay
  # ---------------------------------------------------------------------------
  describe '.recency_decay' do
    it 'returns 1.0 for a just-used tool' do
      result = described_class.recency_decay(Time.now)
      expect(result).to be_within(0.01).of(1.0)
    end

    it 'returns 0.0 for a tool last used more than 24h ago' do
      result = described_class.recency_decay(Time.now - 86_401)
      expect(result).to eq(0.0)
    end

    it 'returns 0.0 for nil' do
      expect(described_class.recency_decay(nil)).to eq(0.0)
    end

    it 'returns a value between 0 and 1 for intermediate ages' do
      result = described_class.recency_decay(Time.now - 43_200)
      expect(result).to be_between(0.0, 1.0)
    end
  end

  # ---------------------------------------------------------------------------
  # keyword_match
  # ---------------------------------------------------------------------------
  describe '.keyword_match' do
    it 'returns 0.0 for empty keywords' do
      expect(described_class.keyword_match('legion.run_task', [])).to eq(0.0)
    end

    it 'returns 0.0 for nil keywords' do
      expect(described_class.keyword_match('legion.run_task', nil)).to eq(0.0)
    end

    it 'returns 1.0 when all keywords match' do
      expect(described_class.keyword_match('legion.run_task', %w[run task])).to eq(1.0)
    end

    it 'returns 0.5 when half the keywords match' do
      expect(described_class.keyword_match('legion.run_task', %w[run status])).to eq(0.5)
    end

    it 'returns 0.0 when no keywords match' do
      expect(described_class.keyword_match('legion.run_task', %w[delete chain])).to eq(0.0)
    end
  end
end
