# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/error'

# Stub extension modules before loading the command
module Legion
  module Extensions
    module Knowledge
      module Runners
        module Query
          class << self
            attr_accessor :test_query_result, :test_retrieve_result
          end

          def self.query(**)
            Legion::Extensions::Knowledge::Runners::Query.test_query_result
          end

          def self.retrieve(**)
            Legion::Extensions::Knowledge::Runners::Query.test_retrieve_result
          end
        end

        module Ingest
          class << self
            attr_accessor :test_ingest_file_result, :test_ingest_corpus_result, :test_scan_result
          end

          def self.ingest_file(**)
            Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_file_result
          end

          def self.ingest_corpus(**)
            Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_corpus_result
          end

          def self.scan_corpus(**)
            Legion::Extensions::Knowledge::Runners::Ingest.test_scan_result
          end
        end
      end
    end
  end
end

require 'legion/cli/knowledge_command'

# Patch require_knowledge! and require_ingest! to be no-ops (extensions already stubbed above)
Legion::CLI::Knowledge.class_eval do
  no_commands do
    define_method(:require_knowledge!) { nil }
    define_method(:require_ingest!) { nil }
  end
end

RSpec.describe Legion::CLI::Knowledge do
  let(:query_result_success) do
    {
      success: true,
      answer:  'Legion uses RabbitMQ for async messaging.',
      sources: [
        { source_file: 'README.md', heading: 'Transport', content: 'RabbitMQ AMQP 0.9.1', score: 0.95 },
        { source_file: 'CLAUDE.md', heading: '',          content: 'legion-transport gem', score: 0.82 }
      ]
    }
  end

  let(:retrieve_result_success) do
    {
      success: true,
      sources: [
        { source_file: 'docs/transport.md', heading: 'Setup', content: 'AMQP connection', score: 0.91 }
      ]
    }
  end

  let(:ingest_file_result_success) do
    { success: true, file_path: '/tmp/doc.md', chunks: 4 }
  end

  let(:ingest_corpus_result_success) do
    { success: true, path: '/tmp/docs', files_ingested: 3, chunks: 12 }
  end

  let(:scan_result) do
    { path: '/tmp/project', file_count: 7, total_bytes: 45_678 }
  end

  before do
    Legion::Extensions::Knowledge::Runners::Query.test_query_result    = query_result_success
    Legion::Extensions::Knowledge::Runners::Query.test_retrieve_result = retrieve_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_file_result   = ingest_file_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_corpus_result = ingest_corpus_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_scan_result = scan_result
  end

  describe '#query' do
    it 'shows Knowledge Query header' do
      expect do
        described_class.start(['query', 'what is legion transport', '--no-color'])
      end.to output(/Knowledge Query/).to_stdout
    end

    it 'prints the synthesized answer' do
      expect do
        described_class.start(['query', 'what is legion transport', '--no-color'])
      end.to output(/RabbitMQ/).to_stdout
    end

    it 'shows source files' do
      expect do
        described_class.start(['query', 'what is legion transport', '--no-color'])
      end.to output(/README\.md/).to_stdout
    end

    it 'passes top_k to Runners::Query.query' do
      expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query)
        .with(hash_including(top_k: 10))
        .and_return(query_result_success)
      described_class.start(['query', 'test question', '--top-k', '10', '--no-color'])
    end

    it 'passes synthesize: true by default' do
      expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query)
        .with(hash_including(synthesize: true))
        .and_return(query_result_success)
      described_class.start(['query', 'test question', '--no-color'])
    end

    it 'passes synthesize: false when --no-synthesize is given' do
      expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query)
        .with(hash_including(synthesize: false))
        .and_return(query_result_success)
      described_class.start(['query', 'test question', '--no-synthesize', '--no-color'])
    end

    context 'with --verbose' do
      it 'prints source content' do
        expect do
          described_class.start(['query', 'test question', '--verbose', '--no-color'])
        end.to output(/RabbitMQ AMQP/).to_stdout
      end
    end

    context 'when query fails' do
      before do
        Legion::Extensions::Knowledge::Runners::Query.test_query_result = { success: false, error: 'embedding unavailable' }
      end

      it 'shows error message' do
        expect do
          described_class.start(['query', 'broken query', '--no-color'])
        end.to output(/embedding unavailable/).to_stdout
      end
    end

    context 'with --json' do
      it 'outputs JSON' do
        expect do
          described_class.start(['query', 'test question', '--json', '--no-color'])
        end.to output(/success/).to_stdout
      end
    end
  end

  describe '#retrieve' do
    it 'shows Knowledge Retrieve header' do
      expect do
        described_class.start(['retrieve', 'AMQP setup', '--no-color'])
      end.to output(/Knowledge Retrieve/).to_stdout
    end

    it 'shows chunk count in header' do
      expect do
        described_class.start(['retrieve', 'AMQP setup', '--no-color'])
      end.to output(/1 chunk/).to_stdout
    end

    it 'shows source file' do
      expect do
        described_class.start(['retrieve', 'AMQP setup', '--no-color'])
      end.to output(/transport\.md/).to_stdout
    end

    it 'passes top_k to Runners::Query.retrieve' do
      expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:retrieve)
        .with(hash_including(top_k: 3))
        .and_return(retrieve_result_success)
      described_class.start(['retrieve', 'test', '--top-k', '3', '--no-color'])
    end

    context 'with --json' do
      it 'outputs JSON' do
        expect do
          described_class.start(['retrieve', 'test', '--json', '--no-color'])
        end.to output(/sources/).to_stdout
      end
    end
  end

  describe '#ingest' do
    context 'with a file path' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'test.md') }

      before { File.write(tmpfile, '# Test') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'calls ingest_file with file_path:' do
        expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:ingest_file)
          .with(hash_including(file_path: tmpfile))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--no-color'])
      end

      it 'shows Ingest complete' do
        expect do
          described_class.start(['ingest', tmpfile, '--no-color'])
        end.to output(/Ingest complete/).to_stdout
      end

      it 'passes force: true when --force given' do
        expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:ingest_file)
          .with(hash_including(force: true))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--force', '--no-color'])
      end

      it 'passes dry_run: true when --dry-run given' do
        expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:ingest_file)
          .with(hash_including(dry_run: true))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--dry-run', '--no-color'])
      end
    end

    context 'with a directory path' do
      let(:tmpdir) { Dir.mktmpdir('knowledge-test') }

      after { FileUtils.rm_rf(tmpdir) }

      it 'calls ingest_corpus with path:' do
        expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:ingest_corpus)
          .with(hash_including(path: tmpdir))
          .and_return(ingest_corpus_result_success)
        described_class.start(['ingest', tmpdir, '--no-color'])
      end

      it 'shows Ingest complete' do
        expect do
          described_class.start(['ingest', tmpdir, '--no-color'])
        end.to output(/Ingest complete/).to_stdout
      end

      it 'passes dry_run: true when --dry-run given' do
        expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:ingest_corpus)
          .with(hash_including(dry_run: true))
          .and_return(ingest_corpus_result_success)
        described_class.start(['ingest', tmpdir, '--dry-run', '--no-color'])
      end
    end

    context 'when ingest fails' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'fail.md') }

      before { File.write(tmpfile, '# Fail') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      before do
        Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_file_result = { success: false, error: 'parse error' }
      end

      it 'shows error message' do
        expect do
          described_class.start(['ingest', tmpfile, '--no-color'])
        end.to output(/parse error/).to_stdout
      end
    end

    context 'with --json' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'json.md') }

      before { File.write(tmpfile, '# JSON') }

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'outputs JSON' do
        expect do
          described_class.start(['ingest', tmpfile, '--json', '--no-color'])
        end.to output(/success/).to_stdout
      end
    end
  end

  describe '#status' do
    it 'shows Knowledge Status header' do
      expect do
        described_class.start(%w[status --no-color])
      end.to output(/Knowledge Status/).to_stdout
    end

    it 'shows file count' do
      expect do
        described_class.start(%w[status --no-color])
      end.to output(/7/).to_stdout
    end

    it 'shows total bytes' do
      expect do
        described_class.start(%w[status --no-color])
      end.to output(/45678/).to_stdout
    end

    it 'calls scan_corpus with Dir.pwd' do
      expect(Legion::Extensions::Knowledge::Runners::Ingest).to receive(:scan_corpus)
        .with(hash_including(path: Dir.pwd))
        .and_return(scan_result)
      described_class.start(%w[status --no-color])
    end

    context 'with --json' do
      it 'outputs JSON' do
        output = capture_stdout { described_class.start(%w[status --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:file_count]).to eq(7)
      end
    end
  end

  describe 'when lex-knowledge is not loaded' do
    before do
      # Temporarily restore the real require_knowledge! guard by removing the patch
      Legion::CLI::Knowledge.class_eval do
        no_commands do
          define_method(:require_knowledge!) do
            raise Legion::CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
          end
          define_method(:require_ingest!) do
            raise Legion::CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
          end
        end
      end
    end

    after do
      # Restore no-op patch for other tests
      Legion::CLI::Knowledge.class_eval do
        no_commands do
          define_method(:require_knowledge!) { nil }
          define_method(:require_ingest!) { nil }
        end
      end
    end

    it 'raises CLI::Error with helpful message on query' do
      expect do
        described_class.start(['query', 'test', '--no-color'])
      end.to raise_error(Legion::CLI::Error, /lex-knowledge extension is not loaded/)
    end

    it 'raises CLI::Error with helpful message on ingest' do
      expect do
        described_class.start(['ingest', '/tmp/doc.md', '--no-color'])
      end.to raise_error(Legion::CLI::Error, /lex-knowledge extension is not loaded/)
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
