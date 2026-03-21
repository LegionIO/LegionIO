# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/registry'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/marketplace'

RSpec.describe 'Marketplace API routes' do
  include Rack::Test::Methods

  let(:entry_attrs) do
    {
      name:        'lex-test',
      version:     '1.0.0',
      author:      'test-author',
      description: 'A test extension',
      risk_tier:   'low',
      airb_status: 'pending',
      status:      :active
    }
  end

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
    loader.settings[:data]      = { connected: false }
    loader.settings[:transport] = { connected: false }
    loader.settings[:extensions] = {}
  end

  before(:each) do
    Legion::Registry.clear!
    Legion::Registry.register(Legion::Registry::Entry.new(**entry_attrs))
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Marketplace
    end
  end

  def app
    test_app
  end

  def json_post(path, body = {})
    post path, Legion::JSON.dump(body), 'CONTENT_TYPE' => 'application/json'
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/marketplace
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/marketplace' do
    it 'returns 200' do
      get '/api/marketplace'
      expect(last_response.status).to eq(200)
    end

    it 'returns data array' do
      get '/api/marketplace'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end

    it 'includes registered extension' do
      get '/api/marketplace'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data].map { |e| e[:name] }).to include('lex-test')
    end

    it 'returns meta with total' do
      get '/api/marketplace'
      body = Legion::JSON.load(last_response.body)
      expect(body[:meta][:total]).to eq(1)
    end

    it 'filters by status query param' do
      Legion::Registry.submit_for_review('lex-test')
      get '/api/marketplace?status=pending_review'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data].size).to eq(1)
    end

    it 'returns empty data when status filter matches nothing' do
      get '/api/marketplace?status=rejected'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_empty
    end

    it 'filters by query param q' do
      get '/api/marketplace?q=test'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data].map { |e| e[:name] }).to include('lex-test')
    end

    it 'returns empty when query matches nothing' do
      get '/api/marketplace?q=zzzmissing'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_empty
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/marketplace/:name
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/marketplace/:name' do
    it 'returns 200 for known extension' do
      get '/api/marketplace/lex-test'
      expect(last_response.status).to eq(200)
    end

    it 'returns extension name in data' do
      get '/api/marketplace/lex-test'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('lex-test')
    end

    it 'returns stats in data' do
      get '/api/marketplace/lex-test'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:stats]).to be_a(Hash)
    end

    it 'returns 404 for unknown extension' do
      get '/api/marketplace/lex-missing'
      expect(last_response.status).to eq(404)
    end

    it 'returns error body for 404' do
      get '/api/marketplace/lex-missing'
      body = Legion::JSON.load(last_response.body)
      expect(body[:error]).not_to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/marketplace/:name/submit
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/marketplace/:name/submit' do
    it 'returns 202 for known extension' do
      json_post '/api/marketplace/lex-test/submit'
      expect(last_response.status).to eq(202)
    end

    it 'sets status to pending_review' do
      json_post '/api/marketplace/lex-test/submit'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('pending_review')
    end

    it 'returns 404 for unknown extension' do
      json_post '/api/marketplace/lex-missing/submit'
      expect(last_response.status).to eq(404)
    end

    it 'transitions registry status' do
      json_post '/api/marketplace/lex-test/submit'
      expect(Legion::Registry.lookup('lex-test').status).to eq(:pending_review)
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/marketplace/:name/approve
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/marketplace/:name/approve' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'returns 200 for known extension' do
      json_post '/api/marketplace/lex-test/approve'
      expect(last_response.status).to eq(200)
    end

    it 'returns approved status' do
      json_post '/api/marketplace/lex-test/approve'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('approved')
    end

    it 'stores notes from request body' do
      json_post '/api/marketplace/lex-test/approve', notes: 'LGTM'
      expect(Legion::Registry.lookup('lex-test').review_notes).to eq('LGTM')
    end

    it 'returns 404 for unknown extension' do
      json_post '/api/marketplace/lex-missing/approve'
      expect(last_response.status).to eq(404)
    end

    it 'transitions registry status to approved' do
      json_post '/api/marketplace/lex-test/approve'
      expect(Legion::Registry.lookup('lex-test').status).to eq(:approved)
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/marketplace/:name/reject
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/marketplace/:name/reject' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'returns 200 for known extension' do
      json_post '/api/marketplace/lex-test/reject'
      expect(last_response.status).to eq(200)
    end

    it 'returns rejected status' do
      json_post '/api/marketplace/lex-test/reject'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('rejected')
    end

    it 'stores reason from request body' do
      json_post '/api/marketplace/lex-test/reject', reason: 'CVE found'
      expect(Legion::Registry.lookup('lex-test').reject_reason).to eq('CVE found')
    end

    it 'returns 404 for unknown extension' do
      json_post '/api/marketplace/lex-missing/reject'
      expect(last_response.status).to eq(404)
    end

    it 'transitions registry status to rejected' do
      json_post '/api/marketplace/lex-test/reject'
      expect(Legion::Registry.lookup('lex-test').status).to eq(:rejected)
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/marketplace/:name/deprecate
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/marketplace/:name/deprecate' do
    it 'returns 200 for known extension' do
      json_post '/api/marketplace/lex-test/deprecate'
      expect(last_response.status).to eq(200)
    end

    it 'returns deprecated status' do
      json_post '/api/marketplace/lex-test/deprecate'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('deprecated')
    end

    it 'stores successor from request body' do
      json_post '/api/marketplace/lex-test/deprecate', successor: 'lex-test-v2'
      expect(Legion::Registry.lookup('lex-test').successor).to eq('lex-test-v2')
    end

    it 'parses sunset_date from request body' do
      json_post '/api/marketplace/lex-test/deprecate', sunset_date: '2027-01-01'
      expect(Legion::Registry.lookup('lex-test').sunset_date).to eq(Date.new(2027, 1, 1))
    end

    it 'returns 404 for unknown extension' do
      json_post '/api/marketplace/lex-missing/deprecate'
      expect(last_response.status).to eq(404)
    end

    it 'transitions registry status to deprecated' do
      json_post '/api/marketplace/lex-test/deprecate'
      expect(Legion::Registry.lookup('lex-test').status).to eq(:deprecated)
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/marketplace/:name/stats
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/marketplace/:name/stats' do
    it 'returns 200 for known extension' do
      get '/api/marketplace/lex-test/stats'
      expect(last_response.status).to eq(200)
    end

    it 'returns install_count in data' do
      get '/api/marketplace/lex-test/stats'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:install_count)
    end

    it 'returns active_instances in data' do
      get '/api/marketplace/lex-test/stats'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:active_instances)
    end

    it 'returns name in data' do
      get '/api/marketplace/lex-test/stats'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('lex-test')
    end

    it 'returns 404 for unknown extension' do
      get '/api/marketplace/lex-missing/stats'
      expect(last_response.status).to eq(404)
    end

    it 'returns error body for 404' do
      get '/api/marketplace/lex-missing/stats'
      body = Legion::JSON.load(last_response.body)
      expect(body[:error]).not_to be_nil
    end
  end
end
