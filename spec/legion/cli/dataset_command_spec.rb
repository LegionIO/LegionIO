# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/dataset_command'

RSpec.describe Legion::CLI::Dataset do
  let(:out) { instance_double(Legion::CLI::Output::Formatter) }
  let(:client) { instance_double('Legion::Extensions::Dataset::Client') }

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:spacer)
    allow(out).to receive(:detail)
    allow(out).to receive(:header)
    allow(out).to receive(:table)

    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)

    stub_const('Legion::Extensions::Dataset::Client', Class.new do
      def initialize(**); end
    end)
    allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(client)

    data_mod = Module.new { def self.db = nil }
    stub_const('Legion::Data', data_mod)
  end

  def build_command(opts = {})
    described_class.new([], { format: 'json' }.merge(opts).merge(json: false, no_color: true, verbose: false))
  end

  def build_json_command(opts = {})
    described_class.new([], { format: 'json' }.merge(opts).merge(json: true, no_color: true, verbose: false))
  end

  def stub_client(cmd)
    allow(cmd).to receive(:with_dataset_client).and_yield(client)
  end

  describe 'class structure' do
    it 'is a Thor subcommand' do
      expect(described_class).to be < Thor
    end

    it 'has list as default task' do
      expect(described_class.default_command).to eq('list')
    end

    it 'responds to list, show, import, export' do
      expect(described_class.commands.keys).to include('list', 'show', 'import', 'export')
    end
  end

  describe '#list' do
    let(:datasets) do
      [
        { name: 'qa-pairs',     description: 'Q&A training data', latest_version: 3, row_count: 150 },
        { name: 'translations', description: 'Translation pairs', latest_version: 1, row_count: 42 }
      ]
    end

    before { allow(client).to receive(:list_datasets).and_return(datasets) }

    it 'renders a table of datasets' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:table).with(%w[name description version row_count], anything)
      cmd.list
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(datasets)
      cmd.list
    end

    it 'warns when no datasets exist' do
      allow(client).to receive(:list_datasets).and_return([])
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:warn).with('No datasets found')
      cmd.list
    end
  end

  describe '#show' do
    let(:dataset_result) do
      {
        name: 'qa-pairs', version: 2, version_id: 5, row_count: 3,
        rows: [
          { row_index: 0, input: 'What is LegionIO?', expected_output: 'An async job engine' },
          { row_index: 1, input: 'How do tasks run?',  expected_output: 'Via RabbitMQ' },
          { row_index: 2, input: 'What is a LEX?',     expected_output: 'An extension gem' }
        ]
      }
    end

    before { allow(client).to receive(:get_dataset).and_return(dataset_result) }

    it 'renders dataset header and rows table' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:header).with('Dataset: qa-pairs')
      expect(out).to receive(:table).with(%w[index input expected_output], anything)
      cmd.show('qa-pairs')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(dataset_result)
      cmd.show('qa-pairs')
    end

    it 'shows error when dataset not found' do
      allow(client).to receive(:get_dataset).and_return({ error: 'not_found' })
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/not_found/)
      expect { cmd.show('missing') }.to raise_error(SystemExit)
    end

    it 'passes version option to get_dataset' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, version: 1)
      stub_client(cmd)
      expect(client).to receive(:get_dataset).with(name: 'qa-pairs', version: 1).and_return(dataset_result)
      cmd.show('qa-pairs')
    end

    it 'warns about more rows when dataset has more than 10' do
      large_result = dataset_result.merge(
        row_count: 15,
        rows:      Array.new(15) { |i| { row_index: i, input: "q#{i}", expected_output: "a#{i}" } }
      )
      allow(client).to receive(:get_dataset).and_return(large_result)
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:warn).with(/5 more rows/)
      cmd.show('qa-pairs')
    end

    it 'warns when dataset has no rows' do
      empty_result = dataset_result.merge(row_count: 0, rows: [])
      allow(client).to receive(:get_dataset).and_return(empty_result)
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:warn).with('No rows in this dataset version')
      cmd.show('qa-pairs')
    end
  end

  describe '#import' do
    let(:import_result) { { created: true, name: 'qa-pairs', version: 1, row_count: 5 } }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/tmp/data.json').and_return(true)
      allow(client).to receive(:import_dataset).and_return(import_result)
    end

    it 'calls import_dataset with name, path, and format' do
      cmd = build_command
      stub_client(cmd)
      expect(client).to receive(:import_dataset).with(
        name: 'qa-pairs', path: '/tmp/data.json', format: 'json', description: nil
      ).and_return(import_result)
      cmd.import('qa-pairs', '/tmp/data.json')
    end

    it 'outputs success message after import' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:success).with(/qa-pairs.*v1.*5 rows/i)
      cmd.import('qa-pairs', '/tmp/data.json')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(import_result)
      cmd.import('qa-pairs', '/tmp/data.json')
    end

    it 'shows error when file does not exist' do
      allow(File).to receive(:exist?).with('/tmp/missing.csv').and_return(false)
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:error).with(/not found/)
      expect { cmd.import('qa-pairs', '/tmp/missing.csv') }.to raise_error(SystemExit)
    end

    it 'passes description option to import_dataset' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false,
                                    format: 'json', description: 'Training set')
      stub_client(cmd)
      expect(client).to receive(:import_dataset).with(
        name: 'qa-pairs', path: '/tmp/data.json', format: 'json', description: 'Training set'
      ).and_return(import_result)
      cmd.import('qa-pairs', '/tmp/data.json')
    end
  end

  describe '#export' do
    let(:export_result) { { exported: true, path: '/tmp/out.json', row_count: 5 } }

    before { allow(client).to receive(:export_dataset).and_return(export_result) }

    it 'calls export_dataset with name, path, and format' do
      cmd = build_command
      stub_client(cmd)
      expect(client).to receive(:export_dataset).with(
        name: 'qa-pairs', path: '/tmp/out.json', format: 'json'
      ).and_return(export_result)
      cmd.export('qa-pairs', '/tmp/out.json')
    end

    it 'outputs success message after export' do
      cmd = build_command
      stub_client(cmd)
      expect(out).to receive(:success).with(%r{5 rows.*/tmp/out\.json}i)
      cmd.export('qa-pairs', '/tmp/out.json')
    end

    it 'outputs JSON when --json is set' do
      cmd = build_json_command
      stub_client(cmd)
      expect(out).to receive(:json).with(export_result)
      cmd.export('qa-pairs', '/tmp/out.json')
    end

    it 'passes version option to export_dataset' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, format: 'json', version: 2)
      stub_client(cmd)
      expect(client).to receive(:export_dataset).with(
        name: 'qa-pairs', path: '/tmp/out.json', format: 'json', version: 2
      ).and_return(export_result)
      cmd.export('qa-pairs', '/tmp/out.json')
    end

    it 'passes csv format option to export_dataset' do
      cmd = described_class.new([], json: false, no_color: true, verbose: false, format: 'csv')
      stub_client(cmd)
      expect(client).to receive(:export_dataset).with(
        name: 'qa-pairs', path: '/tmp/out.csv', format: 'csv'
      ).and_return(export_result)
      cmd.export('qa-pairs', '/tmp/out.csv')
    end
  end
end
