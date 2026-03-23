# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/search_traces'

RSpec.describe Legion::CLI::Chat::Tools::SearchTraces do
  let(:tool) { described_class.new }

  let(:now) { Time.now.utc }

  let(:trace_conversation) do
    {
      trace_id:          'conv-001',
      trace_type:        :episodic,
      content_payload:   '{"peer":"Bob Smith","chat_id":"abc","summary":"Discussed deployment timeline for Q2 release"}',
      strength:          0.6,
      domain_tags:       ['teams', 'conversation', 'peer:Bob Smith'],
      created_at:        now - 3600,
      associated_traces: []
    }
  end

  let(:trace_person) do
    {
      trace_id:          'person-001',
      trace_type:        :semantic,
      content_payload:   '{"displayName":"Alice Johnson","jobTitle":"SRE Lead","department":"Platform"}',
      strength:          0.7,
      domain_tags:       ['teams', 'peer', 'peer:Alice Johnson'],
      created_at:        now - 7200,
      associated_traces: []
    }
  end

  let(:trace_meeting) do
    {
      trace_id:          'meeting-001',
      trace_type:        :episodic,
      content_payload:   '{"subject":"Sprint Planning","startDateTime":"2026-03-20T10:00:00Z"}',
      strength:          0.5,
      domain_tags:       %w[teams meeting],
      created_at:        now - 86_400,
      associated_traces: []
    }
  end

  let(:trace_team) do
    {
      trace_id:          'team-001',
      trace_type:        :semantic,
      content_payload:   '{"team":"Grid Infrastructure","member_count":8,"members":["Bob Smith","Alice Johnson"]}',
      strength:          0.8,
      domain_tags:       ['teams', 'org', 'team:Grid Infrastructure'],
      created_at:        now - 1800,
      associated_traces: []
    }
  end

  let(:all_traces) { [trace_conversation, trace_person, trace_meeting, trace_team] }

  let(:mock_store) do
    store = instance_double('Store')
    allow(store).to receive(:retrieve_by_domain) do |tag, min_strength:, limit:|
      all_traces.select { |t| t[:domain_tags].include?(tag) && t[:strength] >= min_strength }.first(limit)
    end
    allow(store).to receive(:retrieve_by_type) do |type, min_strength:, limit:|
      all_traces.select { |t| t[:trace_type] == type && t[:strength] >= min_strength }.first(limit)
    end
    allow(store).to receive(:all_traces) do |min_strength:|
      all_traces.select { |t| t[:strength] >= min_strength }
    end
    store
  end

  before do
    stub_const('Legion::Extensions::Agentic::Memory::Trace', Module.new)
    allow(Legion::Extensions::Agentic::Memory::Trace).to receive(:shared_store).and_return(mock_store)
  end

  describe '#execute' do
    it 'returns results matching a keyword query' do
      result = tool.execute(query: 'deployment timeline')
      expect(result).to include('deployment')
      expect(result).to include('Bob Smith')
    end

    it 'filters by person name' do
      result = tool.execute(query: 'deployment', person: 'Bob Smith')
      expect(result).to include('Bob Smith')
    end

    it 'filters by domain tag' do
      result = tool.execute(query: 'sprint', domain: 'meeting')
      expect(result).to include('Sprint Planning')
    end

    it 'filters by trace type' do
      result = tool.execute(query: 'SRE', trace_type: 'semantic')
      expect(result).to include('Alice Johnson')
    end

    it 'returns no-match message when query has zero keyword hits' do
      result = tool.execute(query: 'xyznonexistent')
      expect(result).to include('No traces matched')
    end

    it 'returns unavailable message when trace store is not loaded' do
      allow(Legion::Extensions::Agentic::Memory::Trace).to receive(:respond_to?).with(:shared_store).and_return(false)
      result = tool.execute(query: 'test')
      expect(result).to include('not available')
    end

    it 'attempts to require the gem when constant is not defined' do
      hide_const('Legion::Extensions::Agentic::Memory::Trace')
      allow(tool).to receive(:load_trace_gem)
      tool.execute(query: 'test')
      expect(tool).to have_received(:load_trace_gem)
    end

    it 'respects limit parameter' do
      result = tool.execute(query: 'Bob Alice Grid Sprint', limit: 1)
      expect(result).to include('Found 1 matching')
    end

    it 'clamps limit to valid range' do
      result = tool.execute(query: 'teams', limit: 100)
      expect(result).not_to include('Found 100')
    end

    it 'displays trace metadata' do
      result = tool.execute(query: 'deployment')
      expect(result).to include('tags:')
      expect(result).to include('strength:')
    end

    it 'formats age for recent traces' do
      result = tool.execute(query: 'Grid Infrastructure')
      expect(result).to include('m ago')
    end

    it 'formats age for hour-old traces' do
      result = tool.execute(query: 'deployment')
      expect(result).to include('h ago')
    end

    it 'formats age for day-old traces' do
      result = tool.execute(query: 'Sprint Planning')
      expect(result).to include('d ago')
    end
  end

  describe 'payload parsing' do
    it 'handles string payloads that are not JSON' do
      plain_trace = {
        trace_id: 'plain-001', trace_type: :sensory,
        content_payload: 'just a plain text note about servers',
        strength: 0.5, domain_tags: %w[teams], created_at: now,
        associated_traces: []
      }
      all_traces.push(plain_trace)
      result = tool.execute(query: 'servers')
      expect(result).to include('servers')
    end

    it 'handles hash payloads with symbol keys' do
      hash_trace = {
        trace_id: 'hash-001', trace_type: :semantic,
        content_payload: { displayName: 'Carol', jobTitle: 'Engineer' },
        strength: 0.5, domain_tags: %w[teams peer], created_at: now,
        associated_traces: []
      }
      all_traces.push(hash_trace)
      result = tool.execute(query: 'Carol Engineer')
      expect(result).to include('Carol')
    end
  end
end
