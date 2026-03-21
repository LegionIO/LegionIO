# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'legion/notebook/parser'

RSpec.describe Legion::Notebook::Parser do
  let(:notebook_data) do
    {
      'nbformat'       => 4,
      'nbformat_minor' => 5,
      'metadata'       => {
        'kernelspec'    => { 'display_name' => 'Python 3', 'language' => 'python', 'name' => 'python3' },
        'language_info' => { 'name' => 'python' }
      },
      'cells'          => [
        {
          'cell_type' => 'markdown',
          'metadata'  => {},
          'source'    => ['# My Notebook\n', 'Some description']
        },
        {
          'cell_type'       => 'code',
          'metadata'        => {},
          'source'          => ['x = 1\n', 'print(x)'],
          'outputs'         => [
            { 'output_type' => 'stream', 'name' => 'stdout', 'text' => ['1\n'] }
          ],
          'execution_count' => 1
        },
        {
          'cell_type'       => 'code',
          'metadata'        => {},
          'source'          => ['import sys'],
          'outputs'         => [],
          'execution_count' => nil
        }
      ]
    }
  end

  let(:tmpfile) do
    f = Tempfile.new(['notebook', '.ipynb'])
    f.write(JSON.generate(notebook_data))
    f.close
    f
  end

  after { tmpfile.unlink }

  describe '.parse' do
    subject(:result) { described_class.parse(tmpfile.path) }

    it 'returns a hash with metadata, kernel, language, and cells' do
      expect(result).to have_key(:metadata)
      expect(result).to have_key(:kernel)
      expect(result).to have_key(:language)
      expect(result).to have_key(:cells)
    end

    it 'extracts the kernel display name' do
      expect(result[:kernel]).to eq('Python 3')
    end

    it 'extracts the language' do
      expect(result[:language]).to eq('python')
    end

    it 'parses all cells' do
      expect(result[:cells].length).to eq(3)
    end

    it 'preserves metadata' do
      expect(result[:metadata]).to be_a(Hash)
    end

    it 'defaults language to python when missing' do
      data = notebook_data.dup
      data['metadata'] = { 'kernelspec' => {} }
      f = Tempfile.new(['no_lang', '.ipynb'])
      f.write(JSON.generate(data))
      f.close
      result = described_class.parse(f.path)
      expect(result[:language]).to eq('python')
    ensure
      f&.unlink
    end
  end

  describe '.parse_cell' do
    it 'parses a markdown cell' do
      raw = { 'cell_type' => 'markdown', 'source' => ['# Title'] }
      result = described_class.parse_cell(raw)
      expect(result[:type]).to eq('markdown')
      expect(result[:source]).to eq('# Title')
      expect(result[:outputs]).to eq([])
    end

    it 'joins source array into a single string' do
      raw = { 'cell_type' => 'code', 'source' => ['line1\n', 'line2'], 'outputs' => [] }
      result = described_class.parse_cell(raw)
      expect(result[:source]).to eq('line1\nline2')
    end

    it 'parses outputs for code cells' do
      raw = {
        'cell_type' => 'code',
        'source'    => ['print(1)'],
        'outputs'   => [{ 'output_type' => 'stream', 'text' => ['1\n'] }]
      }
      result = described_class.parse_cell(raw)
      expect(result[:outputs].length).to eq(1)
      expect(result[:outputs][0][:output_type]).to eq('stream')
    end

    it 'handles missing outputs gracefully' do
      raw = { 'cell_type' => 'markdown', 'source' => ['text'] }
      result = described_class.parse_cell(raw)
      expect(result[:outputs]).to eq([])
    end
  end

  describe '.parse_output' do
    it 'parses stream output' do
      output = { 'output_type' => 'stream', 'text' => ['hello\n', 'world'] }
      result = described_class.parse_output(output)
      expect(result[:output_type]).to eq('stream')
      expect(result[:text]).to eq('hello\nworld')
    end

    it 'parses execute_result output' do
      output = {
        'output_type'     => 'execute_result',
        'data'            => { 'text/plain' => ['42'] },
        'execution_count' => 1,
        'metadata'        => {}
      }
      result = described_class.parse_output(output)
      expect(result[:output_type]).to eq('execute_result')
      expect(result[:text]).to eq('42')
    end

    it 'parses display_data output' do
      output = {
        'output_type' => 'display_data',
        'data'        => { 'text/plain' => ['<Figure>'] },
        'metadata'    => {}
      }
      result = described_class.parse_output(output)
      expect(result[:output_type]).to eq('display_data')
      expect(result[:text]).to eq('<Figure>')
    end

    it 'parses error output' do
      output = {
        'output_type' => 'error',
        'ename'       => 'NameError',
        'evalue'      => 'name is not defined',
        'traceback'   => []
      }
      result = described_class.parse_output(output)
      expect(result[:output_type]).to eq('error')
      expect(result[:text]).to include('NameError')
      expect(result[:text]).to include('name is not defined')
    end

    it 'handles unknown output type gracefully' do
      output = { 'output_type' => 'unknown', 'text' => ['some text'] }
      result = described_class.parse_output(output)
      expect(result[:output_type]).to eq('unknown')
      expect(result[:text]).to eq('some text')
    end

    it 'handles missing text gracefully' do
      output = { 'output_type' => 'stream' }
      result = described_class.parse_output(output)
      expect(result[:text]).to eq('')
    end
  end
end
