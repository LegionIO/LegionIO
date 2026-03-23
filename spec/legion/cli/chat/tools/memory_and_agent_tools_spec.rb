# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/memory_store'
require 'legion/cli/chat/subagent'
require 'legion/cli/chat/web_search'
require 'legion/cli/chat/tools/save_memory'
require 'legion/cli/chat/tools/search_memory'
require 'legion/cli/chat/tools/spawn_agent'
require 'legion/cli/chat/tools/web_search'

RSpec.describe 'Chat Memory and Agent Tools' do
  describe Legion::CLI::Chat::Tools::SaveMemory do
    let(:tool) { described_class.new }

    before do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:add).and_return('/tmp/.legion/memory.md')
      allow(tool).to receive(:ingest_to_apollo).and_return(nil)
    end

    it 'saves to project memory by default' do
      result = tool.execute(text: 'always use rspec')
      expect(result).to include('project memory')
      expect(Legion::CLI::Chat::MemoryStore).to have_received(:add).with('always use rspec', scope: :project)
    end

    it 'saves to global memory when scope is global' do
      result = tool.execute(text: 'prefer vim', scope: 'global')
      expect(result).to include('global memory')
      expect(Legion::CLI::Chat::MemoryStore).to have_received(:add).with('prefer vim', scope: :global)
    end

    it 'includes the file path in response' do
      result = tool.execute(text: 'test')
      expect(result).to include('/tmp/.legion/memory.md')
    end

    it 'includes apollo confirmation when available' do
      allow(tool).to receive(:ingest_to_apollo).and_return('Also ingested into Apollo knowledge graph.')
      result = tool.execute(text: 'important fact')
      expect(result).to include('project memory')
      expect(result).to include('Apollo knowledge graph')
    end

    it 'omits apollo when unavailable' do
      result = tool.execute(text: 'test')
      expect(result).not_to include('Apollo')
    end

    it 'returns error message on failure' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:add).and_raise(Errno::EACCES, 'Permission denied')
      result = tool.execute(text: 'test')
      expect(result).to include('Error saving memory')
      expect(result).to include('Permission denied')
    end
  end

  describe Legion::CLI::Chat::Tools::SearchMemory do
    let(:tool) { described_class.new }

    before do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:search).and_return([])
      allow(tool).to receive(:search_apollo).and_return(nil)
    end

    it 'returns no-match message when empty' do
      result = tool.execute(query: 'nonexistent')
      expect(result).to include('No matching memories')
    end

    it 'returns formatted memory results' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:search).and_return([
                                                                             { text: 'always use rspec', source: '/project/.legion/memory.md', line: 3 },
                                                                             { text: 'prefer snake_case', source: '/project/.legion/memory.md', line: 5 }
                                                                           ])
      result = tool.execute(query: 'use')
      expect(result).to include('Memory matches (2)')
      expect(result).to include('always use rspec')
      expect(result).to include('prefer snake_case')
    end

    it 'includes apollo knowledge when available' do
      allow(tool).to receive(:search_apollo).and_return([
                                                          { type: 'pattern', content: 'Use YJIT for performance', confidence: 0.95 }
                                                        ])
      result = tool.execute(query: 'performance')
      expect(result).to include('Apollo knowledge (1)')
      expect(result).to include('[pattern] Use YJIT for performance')
      expect(result).to include('confidence: 0.95')
    end

    it 'combines memory and apollo results' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:search).and_return([
                                                                             { text: 'always use rspec', source: 'x', line: 1 }
                                                                           ])
      allow(tool).to receive(:search_apollo).and_return([
                                                          { type: 'fact', content: 'RSpec is the standard test framework', confidence: 0.9 }
                                                        ])
      result = tool.execute(query: 'rspec')
      expect(result).to include('Memory matches (1)')
      expect(result).to include('Apollo knowledge (1)')
    end

    it 'returns only memory when apollo is unavailable' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:search).and_return([
                                                                             { text: 'fact one', source: 'x', line: 1 }
                                                                           ])
      result = tool.execute(query: 'fact')
      expect(result).to include('fact one')
      expect(result).not_to include('Apollo')
    end

    it 'returns error message on failure' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:search).and_raise(StandardError, 'disk error')
      result = tool.execute(query: 'test')
      expect(result).to include('Error searching memory')
      expect(result).to include('disk error')
    end
  end

  describe Legion::CLI::Chat::Tools::SpawnAgent do
    let(:tool) { described_class.new }

    before do
      allow(Legion::CLI::Chat::Subagent).to receive(:spawn).and_return({ id: 'agent-001' })
    end

    it 'starts a subagent and returns confirmation' do
      result = tool.execute(task: 'review the auth module')
      expect(result).to include('agent-001')
      expect(result).to include('review the auth module')
    end

    it 'passes task and model to Subagent.spawn' do
      tool.execute(task: 'fix the bug', model: 'claude-sonnet')
      expect(Legion::CLI::Chat::Subagent).to have_received(:spawn).with(
        hash_including(task: 'fix the bug', model: 'claude-sonnet')
      )
    end

    it 'reports subagent errors' do
      allow(Legion::CLI::Chat::Subagent).to receive(:spawn).and_return({ error: 'concurrency limit reached' })
      result = tool.execute(task: 'test')
      expect(result).to include('Subagent error')
      expect(result).to include('concurrency limit reached')
    end

    it 'returns error message on exception' do
      allow(Legion::CLI::Chat::Subagent).to receive(:spawn).and_raise(StandardError, 'spawn failed')
      result = tool.execute(task: 'test')
      expect(result).to include('Error spawning subagent')
      expect(result).to include('spawn failed')
    end
  end

  describe Legion::CLI::Chat::Tools::WebSearch do
    let(:tool) { described_class.new }

    let(:search_results) do
      {
        query:           'ruby testing',
        results:         [
          { title: 'RSpec Guide', url: 'https://rspec.info', snippet: 'Behaviour driven development for Ruby' },
          { title: 'Minitest Docs', url: 'https://minitest.info', snippet: 'A complete suite of testing facilities' }
        ],
        fetched_content: 'Full page content from RSpec Guide...'
      }
    end

    before do
      allow(Legion::CLI::Chat::WebSearch).to receive(:search).and_return(search_results)
    end

    it 'returns formatted search results' do
      result = tool.execute(query: 'ruby testing')
      expect(result).to include('RSpec Guide')
      expect(result).to include('https://rspec.info')
      expect(result).to include('Behaviour driven development')
    end

    it 'includes fetched content from top result' do
      result = tool.execute(query: 'ruby testing')
      expect(result).to include('Top Result Content')
      expect(result).to include('Full page content from RSpec Guide')
    end

    it 'omits fetched content section when nil' do
      allow(Legion::CLI::Chat::WebSearch).to receive(:search).and_return(
        search_results.merge(fetched_content: nil)
      )
      result = tool.execute(query: 'ruby testing')
      expect(result).not_to include('Top Result Content')
    end

    it 'passes max_results to search' do
      tool.execute(query: 'test', max_results: 3)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search).with('test', max_results: 3)
    end

    it 'returns search error message' do
      allow(Legion::CLI::Chat::WebSearch).to receive(:search).and_raise(
        Legion::CLI::Chat::WebSearch::SearchError, 'No results found.'
      )
      result = tool.execute(query: 'xyznonexistent')
      expect(result).to include('Search error')
      expect(result).to include('No results found')
    end

    it 'returns generic error message on unexpected failure' do
      allow(Legion::CLI::Chat::WebSearch).to receive(:search).and_raise(StandardError, 'network timeout')
      result = tool.execute(query: 'test')
      expect(result).to include('Error:')
      expect(result).to include('network timeout')
    end
  end
end
