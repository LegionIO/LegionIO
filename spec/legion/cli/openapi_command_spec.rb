# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sinatra/base'
require 'legion/cli/output'
require 'legion/cli/openapi_command'
require 'legion/api/openapi'

RSpec.describe Legion::CLI::Openapi do
  before do
    Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
    loader = Legion::Settings.loader
    loader.settings[:client] ||= { name: 'test-node' }
  end

  describe '#generate — stdout' do
    it 'outputs JSON to stdout' do
      output = capture_stdout { described_class.start(['generate']) }
      expect { JSON.parse(output) }.not_to raise_error
    end

    it 'output includes openapi version' do
      output = capture_stdout { described_class.start(['generate']) }
      parsed = JSON.parse(output)
      expect(parsed['openapi']).to eq('3.1.0')
    end

    it 'output includes paths key' do
      output = capture_stdout { described_class.start(['generate']) }
      parsed = JSON.parse(output)
      expect(parsed['paths']).to be_a(Hash)
    end
  end

  describe '#generate — file output' do
    let(:output_path) { File.join(Dir.tmpdir, "legion_openapi_test_#{Process.pid}.json") }

    after { FileUtils.rm_f(output_path) }

    it 'writes JSON to specified file' do
      described_class.start(['generate', '--output', output_path])
      expect(File.exist?(output_path)).to be(true)
    end

    it 'written file contains valid JSON' do
      described_class.start(['generate', '--output', output_path])
      expect { JSON.parse(File.read(output_path)) }.not_to raise_error
    end

    it 'written file includes openapi version' do
      described_class.start(['generate', '--output', output_path])
      parsed = JSON.parse(File.read(output_path))
      expect(parsed['openapi']).to eq('3.1.0')
    end
  end

  describe '#routes' do
    it 'outputs route lines to stdout' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).not_to be_empty
    end

    it 'includes GET method in output' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).to match(/GET/)
    end

    it 'includes /api/health path' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).to include('/api/health')
    end

    it 'includes /api/tasks path' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).to include('/api/tasks')
    end

    it 'includes POST method in output' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).to match(/POST/)
    end

    it 'includes route summaries' do
      output = capture_stdout { described_class.start(['routes']) }
      expect(output).to match(/#\s+\S/)
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
