# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'thor'
require 'legion/cli/output'
require 'legion/cli/error'
require 'legion/cli/knowledge_command'

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
    { path: Dir.pwd, file_count: 7, total_bytes: 45_678 }
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

  let(:monitor_add_result_success) do
    { success: true }
  end

  let(:monitor_remove_result_success) do
    { success: true }
  end

  let(:monitor_list_result) do
    [
      { path: '/opt/docs', label: 'docs', extensions: %w[md rb] },
      { path: '/opt/wiki', label: nil,    extensions: %w[md] }
    ]
  end

  let(:monitor_status_result) do
    { total_monitors: 2, total_files: 47 }
  end

  describe '#query' do
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(query_result_success)
    end

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

    it 'passes top_k to api_post' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/query', hash_including(top_k: 10))
        .and_return(query_result_success)
      described_class.start(['query', 'test question', '--top-k', '10', '--no-color'])
    end

    it 'passes synthesize: true by default' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/query', hash_including(synthesize: true))
        .and_return(query_result_success)
      described_class.start(['query', 'test question', '--no-color'])
    end

    it 'passes synthesize: false when --no-synthesize is given' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/query', hash_including(synthesize: false))
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
        allow_any_instance_of(described_class).to receive(:api_post)
          .and_return({ success: false, error: 'embedding unavailable' })
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
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(retrieve_result_success)
    end

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

    it 'passes top_k to api_post' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/retrieve', hash_including(top_k: 3))
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

      before do
        File.write(tmpfile, '# Test')
        allow_any_instance_of(described_class).to receive(:api_post).and_return(ingest_file_result_success)
      end

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'calls api_post with the expanded file path' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(path: tmpfile))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--no-color'])
      end

      it 'shows Ingest complete' do
        expect do
          described_class.start(['ingest', tmpfile, '--no-color'])
        end.to output(/Ingest complete/).to_stdout
      end

      it 'passes force: true when --force given' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(force: true))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--force', '--no-color'])
      end

      it 'passes dry_run: true when --dry-run given' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(dry_run: true))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--dry-run', '--no-color'])
      end

      it 'omits dry_run from payload when --dry-run not given' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_excluding(:dry_run))
          .and_return(ingest_file_result_success)
        described_class.start(['ingest', tmpfile, '--no-color'])
      end
    end

    context 'with a directory path' do
      let(:tmpdir) { Dir.mktmpdir('knowledge-test') }

      before do
        allow_any_instance_of(described_class).to receive(:api_post).and_return(ingest_corpus_result_success)
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'calls api_post with the expanded directory path' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(path: tmpdir))
          .and_return(ingest_corpus_result_success)
        described_class.start(['ingest', tmpdir, '--no-color'])
      end

      it 'shows Ingest complete' do
        expect do
          described_class.start(['ingest', tmpdir, '--no-color'])
        end.to output(/Ingest complete/).to_stdout
      end

      it 'passes dry_run: true when --dry-run given' do
        expect_any_instance_of(described_class).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(dry_run: true))
          .and_return(ingest_corpus_result_success)
        described_class.start(['ingest', tmpdir, '--dry-run', '--no-color'])
      end
    end

    context 'when ingest fails' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'fail.md') }

      before do
        File.write(tmpfile, '# Fail')
        allow_any_instance_of(described_class).to receive(:api_post)
          .and_return({ success: false, error: 'parse error' })
      end

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'shows error message' do
        expect do
          described_class.start(['ingest', tmpfile, '--no-color'])
        end.to output(/parse error/).to_stdout
      end
    end

    context 'with --json' do
      let(:tmpfile) { File.join(Dir.mktmpdir, 'json.md') }

      before do
        File.write(tmpfile, '# JSON')
        allow_any_instance_of(described_class).to receive(:api_post).and_return(ingest_file_result_success)
      end

      after { FileUtils.rm_rf(File.dirname(tmpfile)) }

      it 'outputs JSON' do
        expect do
          described_class.start(['ingest', tmpfile, '--json', '--no-color'])
        end.to output(/success/).to_stdout
      end
    end
  end

  describe '#status' do
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(scan_result)
    end

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

    it 'calls api_post with Dir.pwd' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/status', hash_including(path: Dir.pwd))
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
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(health_result_success)
    end

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

    it 'calls api_post with a path key' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/health', hash_including(:path))
        .and_return(health_result_success)
      described_class.start(%w[health --no-color])
    end

    it 'passes --corpus-path to api_post' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/health', hash_including(path: '/custom/path'))
        .and_return(health_result_success)
      described_class.start(['health', '--corpus-path', '/custom/path', '--no-color'])
    end

    context 'when health check fails' do
      before do
        allow_any_instance_of(described_class).to receive(:api_post)
          .and_return({ success: false, error: 'DB unreachable' })
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
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(cleanup_result_success)
    end

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
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/maintain', hash_including(dry_run: true))
        .and_return(cleanup_result_success)
      described_class.start(%w[maintain --no-color])
    end

    it 'passes dry_run: false when --no-dry-run given' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/maintain', hash_including(dry_run: false))
        .and_return(cleanup_result_success.merge(dry_run: false))
      described_class.start(%w[maintain --no-dry-run --no-color])
    end

    it 'omits dry run label when --no-dry-run given' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .and_return(cleanup_result_success.merge(dry_run: false))
      expect do
        described_class.start(%w[maintain --no-dry-run --no-color])
      end.to output(/Knowledge Maintain\z|Knowledge Maintain\n/).to_stdout
    end

    it 'passes --corpus-path to api_post' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/maintain', hash_including(path: '/my/corpus'))
        .and_return(cleanup_result_success)
      described_class.start(['maintain', '--corpus-path', '/my/corpus', '--no-color'])
    end

    context 'when maintenance fails' do
      before do
        allow_any_instance_of(described_class).to receive(:api_post)
          .and_return({ success: false, error: 'index locked' })
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
    before do
      allow_any_instance_of(described_class).to receive(:api_post).and_return(quality_result_success)
    end

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

    it 'passes limit to api_post' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/quality', hash_including(limit: 20))
        .and_return(quality_result_success)
      described_class.start(%w[quality --limit 20 --no-color])
    end

    it 'defaults limit to 10' do
      expect_any_instance_of(described_class).to receive(:api_post)
        .with('/api/knowledge/quality', hash_including(limit: 10))
        .and_return(quality_result_success)
      described_class.start(%w[quality --no-color])
    end

    it 'shows (none) for empty chunk sections' do
      allow_any_instance_of(described_class).to receive(:api_post)
        .and_return(quality_result_success.merge(hot_chunks: [], cold_chunks: [], low_confidence: []))
      expect do
        described_class.start(%w[quality --no-color])
      end.to output(/\(none\)/).to_stdout
    end

    context 'when quality report fails' do
      before do
        allow_any_instance_of(described_class).to receive(:api_post)
          .and_return({ success: false, error: 'no index found' })
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

  describe 'monitor subcommand' do
    describe 'add' do
      it 'calls api_post with path and shows success' do
        expect_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_post)
          .with('/api/knowledge/monitors', hash_including(path: '/opt/docs'))
          .and_return(monitor_add_result_success)
        expect do
          Legion::CLI::MonitorCommand.start(['add', '/opt/docs', '--no-color'])
        end.to output(/Monitor added/).to_stdout
      end

      it 'passes extensions as array' do
        expect_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_post)
          .with('/api/knowledge/monitors', hash_including(extensions: %w[md rb]))
          .and_return(monitor_add_result_success)
        Legion::CLI::MonitorCommand.start(['add', '/opt/docs', '--extensions', 'md,rb', '--no-color'])
      end

      it 'passes label option' do
        expect_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_post)
          .with('/api/knowledge/monitors', hash_including(label: 'my-docs'))
          .and_return(monitor_add_result_success)
        Legion::CLI::MonitorCommand.start(['add', '/opt/docs', '--label', 'my-docs', '--no-color'])
      end

      it 'shows error when add fails' do
        allow_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_post)
          .and_return({ success: false, error: 'path not found' })
        expect do
          Legion::CLI::MonitorCommand.start(['add', '/bad/path', '--no-color'])
        end.to output(/path not found/).to_stdout
      end
    end

    describe 'list' do
      before do
        allow_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_get).and_return(monitor_list_result)
      end

      it 'shows monitor paths' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[list --no-color])
        end.to output(%r{/opt/docs}).to_stdout
      end

      it 'shows monitor labels' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[list --no-color])
        end.to output(/docs/).to_stdout
      end

      it 'shows Knowledge Monitors header' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[list --no-color])
        end.to output(/Knowledge Monitors/).to_stdout
      end

      it 'shows no monitors message when list is empty' do
        allow_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_get).and_return([])
        expect do
          Legion::CLI::MonitorCommand.start(%w[list --no-color])
        end.to output(/No monitors registered/).to_stdout
      end
    end

    describe 'remove' do
      it 'calls api_delete with identifier and shows success' do
        expect_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_delete)
          .with(a_string_matching(%r{/api/knowledge/monitors\?identifier=}))
          .and_return(monitor_remove_result_success)
        expect do
          Legion::CLI::MonitorCommand.start(['remove', '/opt/docs', '--no-color'])
        end.to output(/Monitor removed/).to_stdout
      end

      it 'shows error when remove fails' do
        allow_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_delete)
          .and_return({ success: false, error: 'not found' })
        expect do
          Legion::CLI::MonitorCommand.start(['remove', 'nonexistent', '--no-color'])
        end.to output(/not found/).to_stdout
      end
    end

    describe 'status' do
      before do
        allow_any_instance_of(Legion::CLI::MonitorCommand).to receive(:api_get).and_return(monitor_status_result)
      end

      it 'shows total monitors count' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[status --no-color])
        end.to output(/2/).to_stdout
      end

      it 'shows total files count' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[status --no-color])
        end.to output(/47/).to_stdout
      end

      it 'shows Monitor Status header' do
        expect do
          Legion::CLI::MonitorCommand.start(%w[status --no-color])
        end.to output(/Monitor Status/).to_stdout
      end
    end
  end

  describe 'capture subcommand' do
    describe 'commit' do
      it 'outputs something for a valid git repo' do
        git_log_cmd = "git log -1 --format='%H %s' 2>/dev/null"
        git_log_result = "abc1234def5678 add monitor subcommand\n"
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:`).with(git_log_cmd).and_return(git_log_result)
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:`).with('git diff HEAD~1 --stat 2>/dev/null').and_return("1 file changed\n")
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:api_post).and_return({ success: true })
        expect do
          Legion::CLI::CaptureCommand.start(%w[commit --no-color])
        end.to output(/.+/).to_stdout
      end

      it 'shows warning when no git commit found' do
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:`).with("git log -1 --format='%H %s' 2>/dev/null").and_return('')
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:`).with('git diff HEAD~1 --stat 2>/dev/null').and_return('')
        expect do
          Legion::CLI::CaptureCommand.start(%w[commit --no-color])
        end.to output(/No git commit found/).to_stdout
      end
    end

    describe 'transcript' do
      let(:tmpdir)     { Dir.mktmpdir('transcript-test') }
      let(:session_id) { 'test-session-abc-123' }
      let(:jsonl_path) { File.join(tmpdir, "#{session_id}.jsonl") }

      before do
        lines = [
          { type: 'user', message: { role: 'user', content: 'hello world' },
            timestamp: '2026-03-27T10:00:00Z' }.to_json,
          { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'Hi there!' }] },
            timestamp: '2026-03-27T10:00:01Z' }.to_json,
          { type: 'progress', data: { type: 'hook' } }.to_json,
          { type: 'user', message: { role: 'user', content: 'fix the bug' },
            timestamp: '2026-03-27T10:01:00Z' }.to_json,
          { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: 'Done!' }] },
            timestamp: '2026-03-27T10:01:05Z' }.to_json
        ]
        File.write(jsonl_path, "#{lines.join("\n")}\n")

        # Stub resolve_transcript_path to return our temp file
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:resolve_transcript_path).and_return(jsonl_path)
        allow_any_instance_of(Legion::CLI::CaptureCommand)
          .to receive(:`).with(anything).and_return('legion')
      end

      after { FileUtils.rm_rf(tmpdir) }

      it 'warns when no session ID is provided' do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('CLAUDE_SESSION_ID', nil).and_return(nil)
        expect do
          Legion::CLI::CaptureCommand.start(%w[transcript --no-color])
        end.to output(/No session ID/).to_stdout
      end

      it 'ingests conversation turns' do
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', anything).twice
          .and_return({ success: true })
        expect do
          Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--no-color'])
        end.to output(%r{Captured 2/2 turns}).to_stdout
      end

      it 'skips progress entries' do
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', anything).twice
          .and_return({ success: true })
        Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--no-color'])
      end

      it 'respects --max-chunks' do
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', anything).once
          .and_return({ success: true })
        expect do
          Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--max-chunks', '1', '--no-color'])
        end.to output(%r{Captured 1/1 turns}).to_stdout
      end

      it 'tags with session ID' do
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(tags: include("session:#{session_id}")))
          .twice.and_return({ success: true })
        Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--no-color'])
      end

      it 'includes turn content with user and assistant sections' do
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(content: /hello world.*Hi there!/m))
          .and_return({ success: true })
        expect_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
          .with('/api/knowledge/ingest', hash_including(content: /fix the bug.*Done!/m))
          .and_return({ success: true })
        Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--no-color'])
      end

      context 'with --json' do
        it 'outputs JSON with turn count' do
          allow_any_instance_of(Legion::CLI::CaptureCommand).to receive(:api_post)
            .and_return({ success: true })
          output = capture_stdout do
            Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--json', '--no-color'])
          end
          parsed = JSON.parse(output, symbolize_names: true)
          expect(parsed[:turns]).to eq(2)
          expect(parsed[:ingested]).to eq(2)
        end
      end

      context 'when transcript file is missing' do
        before do
          allow_any_instance_of(Legion::CLI::CaptureCommand)
            .to receive(:resolve_transcript_path).and_return('/nonexistent/path.jsonl')
        end

        it 'warns about missing transcript' do
          expect do
            Legion::CLI::CaptureCommand.start(['transcript', '--session-id', session_id, '--no-color'])
          end.to output(/Transcript not found/).to_stdout
        end
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
