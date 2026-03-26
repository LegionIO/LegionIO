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

        module Maintenance
          class << self
            attr_accessor :test_health_result, :test_cleanup_result, :test_quality_result
          end

          def self.health(**)
            Legion::Extensions::Knowledge::Runners::Maintenance.test_health_result
          end

          def self.cleanup_orphans(**)
            Legion::Extensions::Knowledge::Runners::Maintenance.test_cleanup_result
          end

          def self.quality_report(**)
            Legion::Extensions::Knowledge::Runners::Maintenance.test_quality_result
          end
        end
      end
    end
  end
end

require 'legion/cli/knowledge_command'

# Patch require_knowledge!, require_ingest!, require_maintenance! to be no-ops (extensions already stubbed above)
Legion::CLI::Knowledge.class_eval do
  no_commands do
    define_method(:require_knowledge!) { nil }
    define_method(:require_ingest!) { nil }
    define_method(:require_maintenance!) { nil }
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

  let(:health_result_success) do
    {
      success: true,
      local:   { 'chunks' => 42, 'sources' => 5 },
      apollo:  { 'entries' => 38, 'reachable' => true },
      sync:    { 'in_sync' => true, 'drift' => 0 }
    }
  end

  let(:cleanup_result_success) do
    {
      success:       true,
      orphan_files:  ['stale/old.md'],
      archived:      1,
      files_cleaned: 1,
      dry_run:       true
    }
  end

  let(:quality_result_success) do
    {
      success:        true,
      hot_chunks:     [{ id: 1, confidence: 0.95, source_file: 'README.md' }],
      cold_chunks:    [{ id: 2, confidence: 0.10, source_file: 'archive/old.md' }],
      low_confidence: [{ id: 3, confidence: 0.05, source_file: 'draft.md' }],
      summary:        { 'total' => 100, 'healthy' => 88 }
    }
  end

  before do
    Legion::Extensions::Knowledge::Runners::Query.test_query_result    = query_result_success
    Legion::Extensions::Knowledge::Runners::Query.test_retrieve_result = retrieve_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_file_result   = ingest_file_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_ingest_corpus_result = ingest_corpus_result_success
    Legion::Extensions::Knowledge::Runners::Ingest.test_scan_result          = scan_result
    Legion::Extensions::Knowledge::Runners::Maintenance.test_health_result   = health_result_success
    Legion::Extensions::Knowledge::Runners::Maintenance.test_cleanup_result  = cleanup_result_success
    Legion::Extensions::Knowledge::Runners::Maintenance.test_quality_result  = quality_result_success
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

  describe '#health' do
    it 'shows Knowledge Health header' do
      expect do
        described_class.start(%w[health --no-color])
      end.to output(/Knowledge Health/).to_stdout
    end

    it 'shows Local section' do
      expect do
        described_class.start(%w[health --no-color])
      end.to output(/Local/).to_stdout
    end

    it 'shows Apollo section' do
      expect do
        described_class.start(%w[health --no-color])
      end.to output(/Apollo/).to_stdout
    end

    it 'shows Sync section' do
      expect do
        described_class.start(%w[health --no-color])
      end.to output(/Sync/).to_stdout
    end

    it 'calls Maintenance.health with path' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health)
        .with(hash_including(:path))
        .and_return(health_result_success)
      described_class.start(%w[health --no-color])
    end

    it 'passes --corpus-path to health' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health)
        .with(hash_including(path: '/custom/path'))
        .and_return(health_result_success)
      described_class.start(['health', '--corpus-path', '/custom/path', '--no-color'])
    end

    context 'when health check fails' do
      before do
        Legion::Extensions::Knowledge::Runners::Maintenance.test_health_result =
          { success: false, error: 'DB unreachable' }
      end

      it 'shows error message' do
        expect do
          described_class.start(%w[health --no-color])
        end.to output(/DB unreachable/).to_stdout
      end
    end

    context 'with --json' do
      it 'outputs JSON' do
        output = capture_stdout { described_class.start(%w[health --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end
    end
  end

  describe '#maintain' do
    it 'shows Knowledge Maintain header with dry run label' do
      expect do
        described_class.start(%w[maintain --no-color])
      end.to output(/Knowledge Maintain \(dry run\)/).to_stdout
    end

    it 'shows orphan files' do
      expect do
        described_class.start(%w[maintain --no-color])
      end.to output(%r{stale/old\.md}).to_stdout
    end

    it 'defaults dry_run to true' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:cleanup_orphans)
        .with(hash_including(dry_run: true))
        .and_return(cleanup_result_success)
      described_class.start(%w[maintain --no-color])
    end

    it 'passes dry_run: false when --no-dry-run given' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:cleanup_orphans)
        .with(hash_including(dry_run: false))
        .and_return(cleanup_result_success.merge(dry_run: false))
      described_class.start(%w[maintain --no-dry-run --no-color])
    end

    it 'omits dry run label when --no-dry-run given' do
      allow(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:cleanup_orphans)
        .and_return(cleanup_result_success.merge(dry_run: false))
      expect do
        described_class.start(%w[maintain --no-dry-run --no-color])
      end.to output(/Knowledge Maintain\z|Knowledge Maintain\n/).to_stdout
    end

    it 'passes --corpus-path to cleanup_orphans' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:cleanup_orphans)
        .with(hash_including(path: '/my/corpus'))
        .and_return(cleanup_result_success)
      described_class.start(['maintain', '--corpus-path', '/my/corpus', '--no-color'])
    end

    context 'when maintenance fails' do
      before do
        Legion::Extensions::Knowledge::Runners::Maintenance.test_cleanup_result =
          { success: false, error: 'index locked' }
      end

      it 'shows error message' do
        expect do
          described_class.start(%w[maintain --no-color])
        end.to output(/index locked/).to_stdout
      end
    end

    context 'with --json' do
      it 'outputs JSON' do
        output = capture_stdout { described_class.start(%w[maintain --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end
    end
  end

  describe '#quality' do
    it 'shows Knowledge Quality Report header' do
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/Knowledge Quality Report/).to_stdout
    end

    it 'shows Hot Chunks section' do
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/Hot Chunks/).to_stdout
    end

    it 'shows Cold Chunks section' do
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/Cold Chunks/).to_stdout
    end

    it 'shows Low Confidence section' do
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/Low Confidence/).to_stdout
    end

    it 'shows source file names in chunks' do
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/README\.md/).to_stdout
    end

    it 'passes limit to quality_report' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:quality_report)
        .with(hash_including(limit: 20))
        .and_return(quality_result_success)
      described_class.start(%w[quality --limit 20 --no-color])
    end

    it 'defaults limit to 10' do
      expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:quality_report)
        .with(hash_including(limit: 10))
        .and_return(quality_result_success)
      described_class.start(%w[quality --no-color])
    end

    it 'shows (none) for empty chunk sections' do
      allow(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:quality_report)
        .and_return(quality_result_success.merge(hot_chunks: [], cold_chunks: [], low_confidence: []))
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/\(none\)/).to_stdout
    end

    context 'when quality report fails' do
      before do
        Legion::Extensions::Knowledge::Runners::Maintenance.test_quality_result =
          { success: false, error: 'no index found' }
      end

      it 'shows error message' do
        expect do
          described_class.start(%w[quality --no-color])
        end.to output(/no index found/).to_stdout
      end
    end

    context 'with --json' do
      it 'outputs JSON' do
        output = capture_stdout { described_class.start(%w[quality --json --no-color]) }
        parsed = JSON.parse(output, symbolize_names: true)
        expect(parsed[:success]).to eq(true)
      end
    end
  end

  describe '#resolve_corpus_path' do
    let(:instance) { described_class.new([], {}) }

    it 'returns Dir.pwd when no options or settings' do
      allow(instance).to receive(:options).and_return({})
      expect(instance.resolve_corpus_path).to eq(Dir.pwd)
    end

    it 'returns corpus_path option when provided' do
      allow(instance).to receive(:options).and_return({ corpus_path: '/opt/docs' })
      expect(instance.resolve_corpus_path).to eq('/opt/docs')
    end
  end

  describe 'when lex-knowledge is not loaded' do
    before do
      # Temporarily restore the real guards by removing the no-op patch
      Legion::CLI::Knowledge.class_eval do
        no_commands do
          define_method(:require_knowledge!) do
            raise Legion::CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
          end
          define_method(:require_ingest!) do
            raise Legion::CLI::Error, 'lex-knowledge extension is not loaded. Install and enable it first.'
          end
          define_method(:require_maintenance!) do
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
          define_method(:require_maintenance!) { nil }
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

    it 'raises CLI::Error with helpful message on health' do
      expect do
        described_class.start(%w[health --no-color])
      end.to raise_error(Legion::CLI::Error, /lex-knowledge extension is not loaded/)
    end

    it 'raises CLI::Error with helpful message on maintain' do
      expect do
        described_class.start(%w[maintain --no-color])
      end.to raise_error(Legion::CLI::Error, /lex-knowledge extension is not loaded/)
    end

    it 'raises CLI::Error with helpful message on quality' do
      expect do
        described_class.start(%w[quality --no-color])
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
