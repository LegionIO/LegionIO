# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/memory_store'
require 'legion/cli/chat/tools/consolidate_memory'

RSpec.describe Legion::CLI::Chat::Tools::ConsolidateMemory do
  subject(:tool) { described_class.new }

  let(:tmpdir) { Dir.mktmpdir('consolidate-test') }

  after { FileUtils.rm_rf(tmpdir) }

  before do
    allow(Legion::CLI::Chat::MemoryStore).to receive(:project_path).and_return(File.join(tmpdir, 'memory.md'))
    allow(Legion::CLI::Chat::MemoryStore).to receive(:global_path).and_return(File.join(tmpdir, 'global.md'))
  end

  describe '#execute' do
    it 'returns message when no entries exist' do
      result = tool.execute(scope: 'project')
      expect(result).to include('No memory entries found')
    end

    it 'returns message when fewer than 3 entries' do
      2.times { |i| Legion::CLI::Chat::MemoryStore.add("entry #{i}", scope: :project, base_dir: tmpdir) }
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_return(%w[one two])
      result = tool.execute(scope: 'project')
      expect(result).to include('no consolidation needed')
    end

    it 'consolidates entries via LLM' do
      entries = ['Ruby uses AMQP for messaging _(2026-03-20)_',
                 'Ruby uses AMQP _(2026-03-21)_',
                 'Extension system is called LEX _(2026-03-20)_',
                 'LEX stands for Legion Extension _(2026-03-21)_']
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_return(entries)

      fake_response = double('LLMResponse',
                             content: "- Ruby uses AMQP for messaging\n- Extension system is called LEX (Legion Extension)\n")
      fake_session = double('ChatSession')
      allow(fake_session).to receive(:ask).and_return(fake_response)

      llm_mod = Module.new
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::LLM).to receive(:chat_direct).and_return(fake_session)

      result = tool.execute(scope: 'project')
      expect(result).to include('4 -> 2')
      expect(result).to include('2 removed/merged')
    end

    it 'supports dry_run mode' do
      entries = %w[entry1 entry2 entry3]
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_return(entries)

      fake_response = double('LLMResponse', content: "- combined entry\n- entry3\n")
      fake_session = double('ChatSession')
      allow(fake_session).to receive(:ask).and_return(fake_response)

      llm_mod = Module.new
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::LLM).to receive(:chat_direct).and_return(fake_session)

      result = tool.execute(scope: 'project', dry_run: 'true')
      expect(result).to include('Preview')
      expect(result).to include('3 -> 2')
    end

    it 'handles LLM unavailable gracefully' do
      entries = %w[a b c]
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_return(entries)

      hide_const('Legion::LLM')
      result = tool.execute(scope: 'project')
      expect(result).to include('could not generate summary')
    end

    it 'handles global scope' do
      entries = %w[global1 global2 global3]
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).with(scope: :global).and_return(entries)

      fake_response = double('LLMResponse', content: "- global combined\n")
      fake_session = double('ChatSession')
      allow(fake_session).to receive(:ask).and_return(fake_response)

      llm_mod = Module.new
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::LLM).to receive(:chat_direct).and_return(fake_session)

      result = tool.execute(scope: 'global')
      expect(result).to include('global memory')
      expect(result).to include('3 -> 1')
    end

    it 'writes consolidated file with header and timestamp' do
      entries = %w[a b c]
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_return(entries)

      fake_response = double('LLMResponse', content: "- consolidated entry\n")
      fake_session = double('ChatSession')
      allow(fake_session).to receive(:ask).and_return(fake_response)

      llm_mod = Module.new
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::LLM).to receive(:chat_direct).and_return(fake_session)

      tool.execute(scope: 'project')

      path = Legion::CLI::Chat::MemoryStore.project_path
      expect(File).to exist(path)
      content = File.read(path)
      expect(content).to include('# Project Memory')
      expect(content).to include('Consolidated on')
      expect(content).to include('- consolidated entry')
    end

    it 'handles errors gracefully' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list).and_raise(StandardError, 'disk full')
      result = tool.execute(scope: 'project')
      expect(result).to include('Error consolidating memory')
      expect(result).to include('disk full')
    end
  end

  describe '#parse_consolidated' do
    it 'extracts entries from LLM output' do
      text = "- entry one\n- entry two\nsome junk\n- entry three\n"
      result = tool.send(:parse_consolidated, text)
      expect(result).to eq(['entry one', 'entry two', 'entry three'])
    end

    it 'handles empty output' do
      result = tool.send(:parse_consolidated, '')
      expect(result).to eq([])
    end
  end
end
