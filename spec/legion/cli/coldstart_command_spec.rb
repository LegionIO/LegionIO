# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'legion/cli/output'

# Define stub extension modules before loading coldstart command
module Legion
  module Extensions
    module Memory; end

    module Coldstart
      module Runners
        module Ingest
          class << self
            attr_accessor :test_file_result, :test_dir_result
          end

          def ingest_file(**)
            Legion::Extensions::Coldstart::Runners::Ingest.test_file_result
          end

          def preview_ingest(**)
            Legion::Extensions::Coldstart::Runners::Ingest.test_file_result
          end

          def ingest_directory(**)
            Legion::Extensions::Coldstart::Runners::Ingest.test_dir_result
          end
        end

        module Coldstart
          class << self
            attr_accessor :test_progress
          end

          def coldstart_progress
            Legion::Extensions::Coldstart::Runners::Coldstart.test_progress
          end
        end
      end
    end
  end
end

require 'legion/cli/coldstart_command'

# Patch require_coldstart! to be a no-op (extensions already stubbed above)
Legion::CLI::Coldstart.class_eval do
  no_commands do
    define_method(:require_coldstart!) { nil }
  end
end

RSpec.describe Legion::CLI::Coldstart do
  let(:file_result) do
    {
      file:          '/tmp/test/CLAUDE.md',
      file_type:     'claude_md',
      traces_parsed: 5,
      traces_stored: 5,
      traces:        [
        { trace_type: :semantic }, { trace_type: :semantic },
        { trace_type: :episodic }, { trace_type: :episodic },
        { trace_type: :identity }
      ]
    }
  end

  let(:dir_result) do
    {
      directory:    '/tmp/test',
      files_found:  3,
      total_parsed: 12,
      total_stored: 12,
      files:        %w[CLAUDE.md MEMORY.md docs/CLAUDE.md]
    }
  end

  let(:progress_data) do
    {
      firmware_loaded:   true,
      imprint_active:    false,
      imprint_progress:  0.75,
      observation_count: 42,
      calibration_state: 'calibrated',
      current_layer:     'semantic'
    }
  end

  before do
    Legion::Extensions::Coldstart::Runners::Ingest.test_file_result = file_result
    Legion::Extensions::Coldstart::Runners::Ingest.test_dir_result = dir_result
    Legion::Extensions::Coldstart::Runners::Coldstart.test_progress = progress_data
    allow(Net::HTTP).to receive(:post).and_raise(Errno::ECONNREFUSED)
  end

  describe '#ingest' do
    context 'with a file path' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'test.md') }

      before { File.write(tmpfile, '# Test') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'shows ingested file header' do
        expect { described_class.start(['ingest', tmpfile, '--no-color']) }.to output(/Ingested/).to_stdout
      end

      it 'shows trace count' do
        expect { described_class.start(['ingest', tmpfile, '--no-color']) }.to output(/5/).to_stdout
      end

      it 'shows trace type breakdown' do
        expect { described_class.start(['ingest', tmpfile, '--no-color']) }.to output(/semantic/).to_stdout
      end

      it 'outputs JSON when requested' do
        expect { described_class.start(['ingest', tmpfile, '--json', '--no-color']) }.to output(/traces_parsed/).to_stdout
      end
    end

    context 'with a directory path' do
      let(:tmpdir) { Dir.mktmpdir('coldstart-test') }

      after { FileUtils.rm_rf(tmpdir) }

      it 'shows directory ingest header' do
        expect { described_class.start(['ingest', tmpdir, '--no-color']) }.to output(/Directory Ingest/).to_stdout
      end

      it 'shows files found' do
        expect { described_class.start(['ingest', tmpdir, '--no-color']) }.to output(/3/).to_stdout
      end

      it 'lists processed files' do
        expect { described_class.start(['ingest', tmpdir, '--no-color']) }.to output(/CLAUDE\.md/).to_stdout
      end
    end

    context 'with nonexistent path' do
      it 'shows error' do
        expect { described_class.start(['ingest', '/nonexistent/path/xyz', '--no-color']) }.to output(/not found/).to_stdout
      end
    end

    context 'with --dry-run on a file' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'test.md') }

      before { File.write(tmpfile, '# Test') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'shows preview output' do
        expect { described_class.start(['ingest', tmpfile, '--dry-run', '--no-color']) }.to output(/Ingested/).to_stdout
      end
    end

    context 'when result has error' do
      let(:file_result) { { error: 'parse failed' } }
      let(:tmpfile) { File.join(Dir.mktmpdir, 'test.md') }

      before { File.write(tmpfile, '# Test') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'shows error and exits' do
        expect { described_class.start(['ingest', tmpfile, '--no-color']) }.to raise_error(SystemExit)
      end
    end
  end

  describe '#status' do
    it 'shows Cold Start Status header' do
      expect { described_class.start(%w[status --no-color]) }.to output(/Cold Start Status/).to_stdout
    end

    it 'shows imprint progress percentage' do
      expect { described_class.start(%w[status --no-color]) }.to output(/75\.0%/).to_stdout
    end

    it 'shows observation count' do
      expect { described_class.start(%w[status --no-color]) }.to output(/42/).to_stdout
    end

    it 'shows calibration state' do
      expect { described_class.start(%w[status --no-color]) }.to output(/calibrated/).to_stdout
    end

    context 'with --json' do
      it 'outputs JSON with all fields' do
        output = capture_stdout { described_class.start(%w[status --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:firmware_loaded]).to eq(true)
        expect(parsed[:observation_count]).to eq(42)
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
