# frozen_string_literal: true

require 'spec_helper'
require 'legion/notebook/renderer'

RSpec.describe Legion::Notebook::Renderer do
  let(:parsed_notebook) do
    {
      kernel:   'Python 3',
      language: 'python',
      cells:    [
        { type: 'markdown', source: '# Hello', outputs: [] },
        { type: 'code',     source: 'x = 1',   outputs: [{ output_type: 'stream', text: '1' }] },
        { type: 'code',     source: '', outputs: [] }
      ]
    }
  end

  describe '.render_notebook' do
    it 'returns a string' do
      result = described_class.render_notebook(parsed_notebook, color: false)
      expect(result).to be_a(String)
    end

    it 'includes kernel name' do
      result = described_class.render_notebook(parsed_notebook, color: false)
      expect(result).to include('Python 3')
    end

    it 'includes cell headers' do
      result = described_class.render_notebook(parsed_notebook, color: false)
      expect(result).to include('Cell 1')
      expect(result).to include('Cell 2')
    end

    it 'includes cell source content' do
      result = described_class.render_notebook(parsed_notebook, color: false)
      expect(result).to include('# Hello')
      expect(result).to include('x = 1')
    end

    it 'includes output text' do
      result = described_class.render_notebook(parsed_notebook, color: false)
      expect(result).to include('=> 1')
    end

    it 'omits kernel line when kernel is nil' do
      nb = parsed_notebook.merge(kernel: nil)
      result = described_class.render_notebook(nb, color: false)
      expect(result).not_to include('Kernel:')
    end

    it 'does not crash with ANSI codes when color is true' do
      result = described_class.render_notebook(parsed_notebook, color: true)
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end
  end

  describe '.render_cell_header' do
    it 'returns plain label without color' do
      result = described_class.render_cell_header(1, 'code', false)
      expect(result).to eq('[code] Cell 1')
    end

    it 'includes ANSI escape codes with color' do
      result = described_class.render_cell_header(1, 'code', true)
      expect(result).to include("\e[")
    end
  end

  describe '.render_cell_source' do
    it 'returns empty string for empty source' do
      cell = { type: 'code', source: '', outputs: [] }
      result = described_class.render_cell_source(cell, 'python', false)
      expect(result).to eq('')
    end

    it 'returns source for markdown cell without fences' do
      cell = { type: 'markdown', source: '# Title', outputs: [] }
      result = described_class.render_cell_source(cell, 'python', false)
      expect(result).to include('# Title')
    end

    it 'returns highlighted code for code cells' do
      cell = { type: 'code', source: 'print(1)', outputs: [] }
      result = described_class.render_cell_source(cell, 'python', false)
      expect(result).to include('print(1)')
    end
  end

  describe '.render_cell_outputs' do
    it 'returns empty array for no outputs' do
      result = described_class.render_cell_outputs([], false)
      expect(result).to eq([])
    end

    it 'renders non-empty output text' do
      outputs = [{ output_type: 'stream', text: 'hello world' }]
      result = described_class.render_cell_outputs(outputs, false)
      expect(result).not_to be_empty
      expect(result.first).to include('hello world')
    end

    it 'skips outputs with blank text' do
      outputs = [{ output_type: 'stream', text: '   ' }]
      result = described_class.render_cell_outputs(outputs, false)
      expect(result).to eq([])
    end
  end

  describe '.highlight' do
    it 'returns the code string when color is false' do
      result = described_class.highlight('x = 1', 'python', false)
      expect(result).to eq('x = 1')
    end

    it 'returns highlighted string when color is true' do
      result = described_class.highlight('x = 1', 'python', true)
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it 'handles unknown language without raising' do
      result = described_class.highlight('some code', 'unknownlang123', true)
      expect(result).to be_a(String)
    end
  end
end
