# frozen_string_literal: true

require 'spec_helper'
require 'legion/graph/builder'
require 'legion/graph/exporter'

RSpec.describe Legion::Graph do
  describe Legion::Graph::Builder do
    describe '.build' do
      context 'when database is not available' do
        it 'returns empty graph' do
          result = described_class.build
          expect(result[:nodes]).to eq({})
          expect(result[:edges]).to eq([])
        end
      end
    end
  end

  describe Legion::Graph::Exporter do
    let(:graph) do
      {
        nodes: {
          'task_a' => { label: 'Task A', type: 'trigger' },
          'task_b' => { label: 'Task B', type: 'action' },
          'task_c' => { label: 'Task C', type: 'action' }
        },
        edges: [
          { from: 'task_a', to: 'task_b', label: 'on_success', chain_id: 'c1' },
          { from: 'task_b', to: 'task_c', label: '', chain_id: 'c1' }
        ]
      }
    end

    describe '.to_mermaid' do
      it 'starts with graph TD' do
        result = described_class.to_mermaid(graph)
        expect(result).to start_with('graph TD')
      end

      it 'includes node definitions' do
        result = described_class.to_mermaid(graph)
        expect(result).to include('Task A')
        expect(result).to include('Task B')
        expect(result).to include('Task C')
      end

      it 'includes labeled edges' do
        result = described_class.to_mermaid(graph)
        expect(result).to include('on_success')
      end

      it 'uses simple arrow for unlabeled edges' do
        result = described_class.to_mermaid(graph)
        expect(result).to match(/N\d+ --> N\d+/)
      end

      it 'handles empty graph' do
        result = described_class.to_mermaid({ nodes: {}, edges: [] })
        expect(result).to eq('graph TD')
      end
    end

    describe '.to_dot' do
      it 'starts with digraph declaration' do
        result = described_class.to_dot(graph)
        expect(result).to start_with('digraph legion_tasks {')
      end

      it 'ends with closing brace' do
        result = described_class.to_dot(graph)
        expect(result.strip).to end_with('}')
      end

      it 'uses box shape for trigger nodes' do
        result = described_class.to_dot(graph)
        expect(result).to include('shape=box')
      end

      it 'uses ellipse shape for action nodes' do
        result = described_class.to_dot(graph)
        expect(result).to include('shape=ellipse')
      end

      it 'includes edge labels' do
        result = described_class.to_dot(graph)
        expect(result).to include('label="on_success"')
      end

      it 'includes rankdir' do
        result = described_class.to_dot(graph)
        expect(result).to include('rankdir=LR')
      end

      it 'handles empty graph' do
        result = described_class.to_dot({ nodes: {}, edges: [] })
        expect(result).to include('digraph legion_tasks')
        expect(result).to include('}')
      end
    end
  end
end
