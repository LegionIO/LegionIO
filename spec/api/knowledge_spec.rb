# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Knowledge API' do
  include Rack::Test::Methods

  def app = Legion::API

  before(:all) { ApiSpecSetup.configure_settings }

  # Stub the Knowledge runners module tree so require_knowledge_ingest! succeeds
  before do
    stub_const('Legion::Extensions::Knowledge', Module.new) unless defined?(Legion::Extensions::Knowledge)
    stub_const('Legion::Extensions::Knowledge::Runners', Module.new) unless defined?(Legion::Extensions::Knowledge::Runners)
    stub_const('Legion::Extensions::Knowledge::Runners::Ingest', Module.new) unless defined?(Legion::Extensions::Knowledge::Runners::Ingest)
  end

  describe 'POST /api/knowledge/ingest' do
    let(:tmpfile) do
      path = File.join(Dir.mktmpdir, 'test.md')
      File.write(path, '# Test content')
      path
    end
    let(:tmpdir) { Dir.mktmpdir('knowledge-test') }

    after do
      FileUtils.rm_rf(File.dirname(tmpfile)) if File.exist?(tmpfile)
      FileUtils.rm_rf(tmpdir) if File.directory?(tmpdir)
    end

    it 'dispatches a file path to ingest_file with only :file_path and :force' do
      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:ingest_file)
        .with(file_path: tmpfile, force: false)
        .and_return(success: true, chunks_created: 1)

      post '/api/knowledge/ingest',
           Legion::JSON.dump({ path: tmpfile, force: false }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'does not forward :dry_run to ingest_file even when present in the body' do
      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:ingest_file)
        .with(hash_excluding(:dry_run))
        .and_return(success: true, chunks_created: 1)

      post '/api/knowledge/ingest',
           Legion::JSON.dump({ path: tmpfile, force: false, dry_run: true }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'dispatches a directory path to ingest_corpus with :dry_run honored' do
      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:ingest_corpus)
        .with(path: tmpdir, force: false, dry_run: true)
        .and_return(success: true, files_scanned: 0)

      post '/api/knowledge/ingest',
           Legion::JSON.dump({ path: tmpdir, force: false, dry_run: true }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'returns 400 when neither :content nor :path is supplied' do
      post '/api/knowledge/ingest',
           Legion::JSON.dump({ force: false }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_param')
    end
  end

  describe 'POST /api/knowledge/status' do
    let(:tmpdir) { Dir.mktmpdir('knowledge-status-test') }

    around do |example|
      loader = Legion::Settings.loader
      original_knowledge = loader.settings[:knowledge]
      original_env = ENV.fetch('LEGION_CORPUS_PATH', nil)
      loader.settings[:knowledge] = {}
      ENV.delete('LEGION_CORPUS_PATH')
      example.run
    ensure
      loader.settings[:knowledge] = original_knowledge
      if original_env.nil?
        ENV.delete('LEGION_CORPUS_PATH')
      else
        ENV['LEGION_CORPUS_PATH'] = original_env
      end
      FileUtils.rm_rf(tmpdir) if File.directory?(tmpdir)
    end

    it 'returns 400 when body path, knowledge.default_corpus_path, and LEGION_CORPUS_PATH are all unset' do
      post '/api/knowledge/status',
           Legion::JSON.dump({}),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_param')
    end

    it 'does NOT default to the daemon cwd (Dir.pwd) when no path source is configured' do
      expect(Legion::Extensions::Knowledge::Runners::Ingest).not_to receive(:scan_corpus)

      post '/api/knowledge/status',
           Legion::JSON.dump({}),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
    end

    it 'uses knowledge.default_corpus_path when set and body has no path' do
      Legion::Settings.loader.settings[:knowledge] = { default_corpus_path: tmpdir }

      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:scan_corpus)
        .with(path: tmpdir)
        .and_return(success: true, path: tmpdir, file_count: 0, total_bytes: 0)

      post '/api/knowledge/status',
           Legion::JSON.dump({}),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'uses LEGION_CORPUS_PATH env var when knowledge.default_corpus_path is not set' do
      ENV['LEGION_CORPUS_PATH'] = tmpdir

      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:scan_corpus)
        .with(path: tmpdir)
        .and_return(success: true, path: tmpdir, file_count: 0, total_bytes: 0)

      post '/api/knowledge/status',
           Legion::JSON.dump({}),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'prefers an explicit body[:path] over knowledge.default_corpus_path and LEGION_CORPUS_PATH' do
      Legion::Settings.loader.settings[:knowledge] = { default_corpus_path: '/settings/path' }
      ENV['LEGION_CORPUS_PATH'] = '/env/path'

      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:scan_corpus)
        .with(path: tmpdir)
        .and_return(success: true, path: tmpdir, file_count: 0, total_bytes: 0)

      post '/api/knowledge/status',
           Legion::JSON.dump({ path: tmpdir }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'prefers knowledge.default_corpus_path over LEGION_CORPUS_PATH' do
      Legion::Settings.loader.settings[:knowledge] = { default_corpus_path: tmpdir }
      ENV['LEGION_CORPUS_PATH'] = '/env/path'

      expect(Legion::Extensions::Knowledge::Runners::Ingest)
        .to receive(:scan_corpus)
        .with(path: tmpdir)
        .and_return(success: true, path: tmpdir, file_count: 0, total_bytes: 0)

      post '/api/knowledge/status',
           Legion::JSON.dump({}),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end
  end
end
