# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/trigger_dream'

RSpec.describe Legion::CLI::Chat::Tools::TriggerDream do
  subject(:tool) { described_class.new }

  before { allow(tool).to receive(:api_port).and_return(4567) }

  describe '#execute' do
    context 'trigger action' do
      it 'triggers dream cycle on daemon' do
        allow(tool).to receive(:api_post).and_return({ data: { task_id: 42 } })

        result = tool.execute
        expect(result).to include('Dream cycle triggered')
        expect(result).to include('Task ID: 42')
      end

      it 'handles API error' do
        allow(tool).to receive(:api_post).and_return({ error: { message: 'runner not found' } })

        result = tool.execute
        expect(result).to include('Dream trigger failed')
        expect(result).to include('runner not found')
      end

      it 'handles connection refused' do
        allow(tool).to receive(:api_post).and_raise(Errno::ECONNREFUSED)

        result = tool.execute
        expect(result).to include('Legion daemon not running')
      end
    end

    context 'journal action' do
      it 'reads the latest dream journal entry' do
        journal_content = "# Dream Cycle\n\n## Phase 1: Memory Audit\n- Traces decayed: 5"
        allow(tool).to receive(:find_latest_journal).and_return('/tmp/dream-test.md')
        allow(File).to receive(:read).with('/tmp/dream-test.md', encoding: 'utf-8').and_return(journal_content)

        result = tool.execute(action: 'journal')
        expect(result).to include('Dream Cycle')
        expect(result).to include('Memory Audit')
      end

      it 'reports when no journal entries found' do
        allow(tool).to receive(:find_latest_journal).and_return(nil)

        result = tool.execute(action: 'journal')
        expect(result).to include('No dream journal entries found')
      end

      it 'truncates long journal entries' do
        long_content = 'x' * 3000
        allow(tool).to receive(:find_latest_journal).and_return('/tmp/dream-long.md')
        allow(File).to receive(:read).with('/tmp/dream-long.md', encoding: 'utf-8').and_return(long_content)

        result = tool.execute(action: 'journal')
        expect(result.length).to be <= 2000
        expect(result).to end_with('...')
      end
    end
  end
end
