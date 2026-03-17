# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'legion/cli/notebook_command'

RSpec.describe Legion::CLI::Notebook do
  let(:cli) { described_class.new }
  let(:notebook) do
    {
      'cells'    => [
        { 'cell_type' => 'markdown', 'source' => ['# Test Notebook'] },
        { 'cell_type' => 'code', 'source' => ['print("hello")'] }
      ],
      'metadata' => { 'kernelspec' => { 'language' => 'python' } }
    }
  end

  let(:tmpfile) do
    f = Tempfile.new(['test', '.ipynb'])
    f.write(JSON.generate(notebook))
    f.close
    f
  end

  after { tmpfile.unlink }

  describe '#read' do
    it 'reads notebook without error' do
      expect { cli.read(tmpfile.path) }.to output(/2 cells total/).to_stdout
    end
  end

  describe '#export' do
    it 'exports as markdown by default' do
      expect { cli.export(tmpfile.path) }.to output(/```python/).to_stdout
    end
  end
end
