# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/memory_status'

RSpec.describe Legion::CLI::Chat::Tools::MemoryStatus do
  subject(:tool) { described_class.new }

  before do
    allow(tool).to receive(:api_port).and_return(4567)
  end

  describe '#execute' do
    context 'with overview action' do
      it 'shows memory and session counts' do
        allow(tool).to receive(:memory_stats).and_return({ project: 2, global: 1 })
        allow(tool).to receive(:session_list).and_return([{ name: 'session1' }])
        allow(tool).to receive(:apollo_stats).and_return(nil)

        result = tool.execute
        expect(result).to include('Memory & Knowledge Overview')
        expect(result).to include('2 project, 1 global')
        expect(result).to include('Saved Sessions: 1')
      end

      it 'shows apollo stats when available' do
        allow(tool).to receive(:memory_stats).and_return({ project: 0, global: 0 })
        allow(tool).to receive(:session_list).and_return([])
        allow(tool).to receive(:apollo_stats).and_return(
          { total: 500, confirmed: 400, disputed: 5, candidates: 95 }
        )

        result = tool.execute
        expect(result).to include('500 entries')
        expect(result).to include('400 confirmed')
        expect(result).to include('5 disputed')
      end
    end

    context 'with memories action' do
      it 'lists project and global memory entries' do
        allow(tool).to receive(:format_memories).and_return(
          "Persistent Memory Detail:\n\n  Project Memory:\n    1. use bun for install\n    2. prefer postgres\n\n  Global Memory:\n    1. timezone: CT"
        )

        result = tool.execute(action: 'memories')
        expect(result).to include('use bun for install')
        expect(result).to include('prefer postgres')
        expect(result).to include('timezone: CT')
      end
    end

    context 'with apollo action' do
      it 'shows knowledge store statistics' do
        allow(tool).to receive(:apollo_stats).and_return(
          { total: 300, confirmed: 250, candidates: 40, disputed: 10,
            recent_24h: 15, avg_confidence: 0.87,
            domains: { 'infrastructure' => 120, 'security' => 80 } }
        )

        result = tool.execute(action: 'apollo')
        expect(result).to include('Total Entries:  300')
        expect(result).to include('Avg Confidence: 0.87')
        expect(result).to include('infrastructure')
      end

      it 'handles apollo unavailable' do
        allow(tool).to receive(:apollo_stats).and_return(nil)

        result = tool.execute(action: 'apollo')
        expect(result).to include('not available')
      end
    end

    context 'with sessions action' do
      it 'lists saved sessions' do
        session_output = [
          "Saved Sessions (2):\n",
          '  debug-cache             24 msgs  1h ago  claude-sonnet-4-6',
          '    Debugging cache issues',
          '  feature-auth            50 msgs  1d ago  claude-sonnet-4-6',
          '    Auth feature implementation'
        ].join("\n")
        allow(tool).to receive(:format_sessions).and_return(session_output)

        result = tool.execute(action: 'sessions')
        expect(result).to include('debug-cache')
        expect(result).to include('feature-auth')
        expect(result).to include('Debugging cache')
      end

      it 'handles no sessions' do
        allow(tool).to receive(:format_sessions).and_return('No saved sessions found.')

        result = tool.execute(action: 'sessions')
        expect(result).to include('No saved sessions')
      end
    end
  end
end
