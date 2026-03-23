# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/memory_command'
require 'legion/cli/chat/memory_store'

RSpec.describe Legion::CLI::Memory do
  let(:store) { Legion::CLI::Chat::MemoryStore }

  before do
    allow(store).to receive(:list).and_return([])
    allow(store).to receive(:add).and_return('/tmp/test/memory.md')
    allow(store).to receive(:forget).and_return(0)
    allow(store).to receive(:search).and_return([])
    allow(store).to receive(:clear).and_return(false)
  end

  describe '#list' do
    context 'with entries' do
      before do
        allow(store).to receive(:list).and_return(['entry one _(2026-03-23)_', 'entry two _(2026-03-23)_'])
      end

      it 'outputs header with count' do
        expect { described_class.start(%w[list --no-color]) }.to output(/Project Memory \(2 entries\)/).to_stdout
      end

      it 'shows entries' do
        expect { described_class.start(%w[list --no-color]) }.to output(/entry one/).to_stdout
      end

      it 'outputs JSON when requested' do
        output = capture_stdout { described_class.start(%w[list --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:entries]).to be_an(Array)
        expect(parsed[:scope]).to eq('project')
      end
    end

    context 'with no entries' do
      it 'shows warning' do
        expect { described_class.start(%w[list --no-color]) }.to output(/No memory entries found/).to_stdout
      end
    end

    context 'with --global flag' do
      it 'uses global scope' do
        described_class.start(%w[list --global --no-color])
        expect(store).to have_received(:list).with(hash_including(scope: :global))
      end
    end
  end

  describe '#add' do
    it 'adds entry and shows success' do
      expect { described_class.start(['add', 'new fact', '--no-color']) }.to output(/Added to project memory/).to_stdout
    end

    it 'passes text to MemoryStore' do
      described_class.start(['add', 'new fact', '--no-color'])
      expect(store).to have_received(:add).with('new fact', scope: :project)
    end
  end

  describe '#forget' do
    context 'when entries match' do
      before { allow(store).to receive(:forget).and_return(2) }

      it 'shows removed count' do
        expect { described_class.start(['forget', 'old', '--no-color']) }.to output(/Removed 2/).to_stdout
      end
    end

    context 'when no entries match' do
      it 'shows warning' do
        expect { described_class.start(['forget', 'nope', '--no-color']) }.to output(/No entries matching/).to_stdout
      end
    end
  end

  describe '#search' do
    context 'with results' do
      before do
        allow(store).to receive(:search).and_return([
                                                      { source: '/project/.legion/memory.md', line: 3,
                                                        text: 'Ruby is great' }
                                                    ])
      end

      it 'shows results' do
        expect { described_class.start(['search', 'ruby', '--no-color']) }.to output(/Ruby is great/).to_stdout
      end

      it 'outputs JSON when requested' do
        output = capture_stdout { described_class.start(['search', 'ruby', '--json', '--no-color']) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:results]).to be_an(Array)
        expect(parsed[:query]).to eq('ruby')
      end
    end

    context 'with no results' do
      it 'shows warning' do
        expect { described_class.start(['search', 'nope', '--no-color']) }.to output(/No results/).to_stdout
      end
    end
  end

  describe '#clear' do
    context 'with --yes flag' do
      before { allow(store).to receive(:clear).and_return(true) }

      it 'clears memory and shows success' do
        expect { described_class.start(%w[clear --yes --no-color]) }.to output(/memory cleared/).to_stdout
      end
    end

    context 'when no memory file exists' do
      it 'shows warning' do
        expect { described_class.start(%w[clear --yes --no-color]) }.to output(/No memory file/).to_stdout
      end
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
