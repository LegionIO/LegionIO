# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'tmpdir'
require 'legion/cli'
require 'legion/cli/notebook_command'

RSpec.describe Legion::CLI::Notebook do
  let(:cli) { described_class.new }
  let(:notebook) do
    {
      'cells'          => [
        {
          'cell_type' => 'markdown',
          'source'    => ['# Test Notebook'],
          'metadata'  => {}
        },
        {
          'cell_type'       => 'code',
          'source'          => ['print("hello")'],
          'outputs'         => [],
          'execution_count' => nil,
          'metadata'        => {}
        }
      ],
      'metadata'       => {
        'kernelspec'    => { 'language' => 'python', 'display_name' => 'Python 3', 'name' => 'python3' },
        'language_info' => { 'name' => 'python' }
      },
      'nbformat'       => 4,
      'nbformat_minor' => 5
    }
  end

  let(:tmpfile) do
    f = Tempfile.new(['test', '.ipynb'])
    f.write(JSON.generate(notebook))
    f.close
    f
  end

  after { tmpfile.unlink }

  describe 'class structure' do
    it 'is a Thor subcommand' do
      expect(described_class).to be < Thor
    end

    it 'defines read, cells, export, and create commands' do
      expect(described_class.commands.keys).to include('read', 'cells', 'export', 'create')
    end

    it 'exits on failure' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe '#read' do
    it 'reads notebook without error' do
      expect { cli.read(tmpfile.path) }.to output(/2 cell/).to_stdout
    end

    it 'prints cells total' do
      expect { cli.read(tmpfile.path) }.to output(/2 cells total/).to_stdout
    end

    it 'exits when file does not exist' do
      expect { cli.read('/nonexistent/file.ipynb') }.to raise_error(SystemExit)
    end

    it 'exits when file is not .ipynb' do
      f = Tempfile.new(['test', '.txt'])
      f.write('{}')
      f.close
      expect { cli.read(f.path) }.to raise_error(SystemExit)
    ensure
      f&.unlink
    end

    it 'exits on invalid JSON' do
      f = Tempfile.new(['bad', '.ipynb'])
      f.write('not json')
      f.close
      expect { cli.read(f.path) }.to raise_error(SystemExit)
    ensure
      f&.unlink
    end
  end

  describe '#cells' do
    it 'lists cells with index numbers' do
      expect { cli.cells(tmpfile.path) }.to output(/1.*markdown|2.*code/m).to_stdout
    end

    it 'shows total count' do
      expect { cli.cells(tmpfile.path) }.to output(/Total: 2 cells/).to_stdout
    end

    it 'exits when file does not exist' do
      expect { cli.cells('/nonexistent/file.ipynb') }.to raise_error(SystemExit)
    end
  end

  describe '#export' do
    it 'exports as markdown by default' do
      expect { cli.export(tmpfile.path) }.to output(/```python/).to_stdout
    end

    it 'includes markdown cell source in output' do
      expect { cli.export(tmpfile.path) }.to output(/Test Notebook/).to_stdout
    end

    it 'exports as script when --format script' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    format: 'script', output: nil)
      expect { cmd.export(tmpfile.path) }.to output(/print\("hello"\)/).to_stdout
    end

    it 'comments markdown cells in script mode' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    format: 'script', output: nil)
      expect { cmd.export(tmpfile.path) }.to output(/# /).to_stdout
    end

    it 'writes to file when --output is given' do
      out_file = Tempfile.new(['export', '.md'])
      out_file.close
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    format: 'md', output: out_file.path)
      cmd.export(tmpfile.path)
      expect(File.read(out_file.path)).to include('```python')
    ensure
      out_file&.unlink
    end

    it 'exits when file does not exist' do
      expect { cli.export('/nonexistent/file.ipynb') }.to raise_error(SystemExit)
    end
  end

  describe '#create' do
    let(:llm_mod) { Module.new }
    let(:out)     { instance_double(Legion::CLI::Output::Formatter) }
    let(:generated_notebook) do
      {
        'nbformat'       => 4,
        'nbformat_minor' => 5,
        'metadata'       => { 'kernelspec' => { 'name' => 'python3' } },
        'cells'          => [
          { 'cell_type' => 'markdown', 'source' => ['# Generated'], 'metadata' => {}, 'outputs' => [] },
          { 'cell_type' => 'code',     'source' => ['print("hi")'], 'metadata' => {}, 'outputs' => [],
            'execution_count' => nil }
        ]
      }
    end

    before do
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::LLM).to receive(:chat).and_return({
                                                        content: JSON.generate(generated_notebook),
                                                        usage:   {}
                                                      })
      allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
      allow(out).to receive(:success)
      allow(out).to receive(:error)
      allow(out).to receive(:json)
      allow(out).to receive(:spacer)
      allow(Legion::CLI::Connection).to receive(:config_dir=)
      allow(Legion::CLI::Connection).to receive(:log_level=)
      allow(Legion::CLI::Connection).to receive(:ensure_llm)
      allow(Legion::CLI::Connection).to receive(:shutdown)
    end

    def tmp_ipynb_path
      File.join(Dir.tmpdir, "legion_nb_test_#{Process.pid}_#{rand(100_000)}.ipynb")
    end

    it 'creates a notebook file' do
      path = tmp_ipynb_path
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    description: 'A test notebook', kernel: 'python3')
      cmd.create(path)
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data['nbformat']).to eq(4)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end

    it 'shows error when description is missing' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    kernel: 'python3')
      expect(out).to receive(:error).with(/--description is required/)
      expect { cmd.create('/tmp/test.ipynb') }.to raise_error(SystemExit)
    end

    it 'passes model option to LLM when provided' do
      path = tmp_ipynb_path
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    description: 'hello', kernel: 'python3', model: 'claude-opus-4-5')
      expect(Legion::LLM).to receive(:chat)
        .with(hash_including(model: 'claude-opus-4-5'))
        .and_return({ content: JSON.generate(generated_notebook), usage: {} })
      cmd.create(path)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end

    it 'passes provider option as symbol to LLM when provided' do
      path = tmp_ipynb_path
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    description: 'hello', kernel: 'python3', provider: 'anthropic')
      expect(Legion::LLM).to receive(:chat)
        .with(hash_including(provider: :anthropic))
        .and_return({ content: JSON.generate(generated_notebook), usage: {} })
      cmd.create(path)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end

    it 'outputs JSON when --json flag is set' do
      path = tmp_ipynb_path
      cmd = described_class.new([], json: true, no_color: true, verbose: false,
                                    description: 'hello', kernel: 'python3')
      expect(out).to receive(:json).with(hash_including(cells: 2))
      cmd.create(path)
    ensure
      File.unlink(path) if path && File.exist?(path)
    end
  end

  describe 'private helpers' do
    describe '#load_notebook' do
      it 'returns parsed JSON for valid .ipynb' do
        result = cli.send(:load_notebook, tmpfile.path, instance_double(Legion::CLI::Output::Formatter))
        expect(result['cells'].length).to eq(2)
      end

      it 'raises SystemExit for missing file' do
        out = instance_double(Legion::CLI::Output::Formatter)
        allow(out).to receive(:error)
        expect { cli.send(:load_notebook, '/no/such/file.ipynb', out) }.to raise_error(SystemExit)
      end

      it 'raises SystemExit for non-.ipynb extension' do
        f = Tempfile.new(['test', '.json'])
        f.write('{}')
        f.close
        out = instance_double(Legion::CLI::Output::Formatter)
        allow(out).to receive(:error)
        expect { cli.send(:load_notebook, f.path, out) }.to raise_error(SystemExit)
      ensure
        f&.unlink
      end

      it 'raises SystemExit for invalid JSON' do
        f = Tempfile.new(['bad', '.ipynb'])
        f.write('not valid json {{')
        f.close
        out = instance_double(Legion::CLI::Output::Formatter)
        allow(out).to receive(:error)
        expect { cli.send(:load_notebook, f.path, out) }.to raise_error(SystemExit)
      ensure
        f&.unlink
      end
    end

    describe '#export_as_markdown' do
      it 'wraps code cells in fenced code blocks' do
        cells = [{ type: 'code', source: 'x = 1', outputs: [] }]
        result = cli.send(:export_as_markdown, cells, 'python')
        expect(result).to include('```python')
        expect(result).to include('x = 1')
        expect(result).to include('```')
      end

      it 'includes markdown cells as plain text' do
        cells = [{ type: 'markdown', source: '# Title', outputs: [] }]
        result = cli.send(:export_as_markdown, cells, 'python')
        expect(result).to include('# Title')
        expect(result).not_to include('```')
      end
    end

    describe '#export_as_script' do
      it 'includes code cells as-is' do
        cells = [{ type: 'code', source: 'x = 1', outputs: [] }]
        result = cli.send(:export_as_script, cells, 'python')
        expect(result).to include('x = 1')
      end

      it 'comments out markdown cells' do
        cells = [{ type: 'markdown', source: '# Title', outputs: [] }]
        result = cli.send(:export_as_script, cells, 'python')
        expect(result).to include('# # Title')
      end
    end
  end
end
