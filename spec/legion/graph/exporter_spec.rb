# frozen_string_literal: true

require 'spec_helper'
require 'legion/graph/exporter'

RSpec.describe Legion::Graph::Exporter do
  let(:graph) do
    {
      nodes: {
        'a' => { label: 'TaskA', type: 'trigger' },
        'b' => { label: 'TaskB', type: 'action' }
      },
      edges: [{ from: 'a', to: 'b', label: 'process' }]
    }
  end

  let(:empty_label_graph) do
    {
      nodes: {
        'x' => { label: 'X', type: 'trigger' },
        'y' => { label: 'Y', type: 'action' }
      },
      edges: [{ from: 'x', to: 'y', label: '' }]
    }
  end

  describe '.to_mermaid' do
    it 'produces valid mermaid syntax' do
      output = described_class.to_mermaid(graph)
      expect(output).to include('graph TD')
      expect(output).to include('-->|process|')
    end

    it 'handles edges without labels' do
      output = described_class.to_mermaid(empty_label_graph)
      expect(output).to include('-->')
      expect(output).not_to include('-->|')
    end
  end

  describe '.to_dot' do
    it 'produces valid DOT syntax' do
      output = described_class.to_dot(graph)
      expect(output).to include('digraph legion_tasks')
      expect(output).to include('"a" -> "b"')
      expect(output).to include('shape=box')
      expect(output).to include('shape=ellipse')
    end

    it 'includes edge labels in DOT output' do
      output = described_class.to_dot(graph)
      expect(output).to include('label="process"')
    end
  end
end
