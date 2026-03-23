# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'legion/cli/graph_command'

RSpec.describe Legion::CLI::GraphCommand do
  let(:graph_data) do
    {
      nodes: {
        'lex-http.fetch'      => { label: 'lex-http.fetch', type: 'trigger' },
        'lex-transform.parse' => { label: 'lex-transform.parse', type: 'action' }
      },
      edges: [
        { from: 'lex-http.fetch', to: 'lex-transform.parse', label: 'on_success', chain_id: 'chain-1' }
      ]
    }
  end

  before do
    allow(Legion::Graph::Builder).to receive(:build).and_return(graph_data)
  end

  describe '#show' do
    it 'renders mermaid format by default' do
      expect { described_class.start(%w[show]) }.to output(/graph TD/).to_stdout
    end

    it 'includes node labels in mermaid output' do
      expect { described_class.start(%w[show]) }.to output(/lex-http\.fetch/).to_stdout
    end

    it 'includes edge labels in mermaid output' do
      expect { described_class.start(%w[show]) }.to output(/on_success/).to_stdout
    end

    it 'renders dot format when requested' do
      expect { described_class.start(%w[show --format dot]) }.to output(/digraph legion_tasks/).to_stdout
    end

    it 'includes shape attributes in dot output' do
      expect { described_class.start(%w[show --format dot]) }.to output(/shape=box/).to_stdout
    end

    it 'writes to file when --output specified' do
      tmpfile = File.join(Dir.mktmpdir, 'graph.md')
      expect { described_class.start(['show', '--output', tmpfile]) }.to output(/Written to/).to_stdout
      content = File.read(tmpfile)
      expect(content).to include('graph TD')
      FileUtils.rm_rf(File.dirname(tmpfile))
    end

    it 'passes chain filter to builder' do
      described_class.start(%w[show --chain chain-42])
      expect(Legion::Graph::Builder).to have_received(:build).with(hash_including(chain_id: 'chain-42'))
    end

    it 'passes limit to builder' do
      described_class.start(%w[show --limit 50])
      expect(Legion::Graph::Builder).to have_received(:build).with(hash_including(limit: 50))
    end

    context 'with empty graph' do
      let(:graph_data) { { nodes: {}, edges: [] } }

      it 'renders minimal mermaid output' do
        expect { described_class.start(%w[show]) }.to output(/graph TD/).to_stdout
      end
    end
  end
end
