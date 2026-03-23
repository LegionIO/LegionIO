# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'sequel'
require 'legion/api/helpers'
require 'legion/api/costs'

RSpec.describe 'Costs API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))

    @db = Sequel.sqlite
    @db.create_table(:metering_records) do
      primary_key :id
      String  :worker_id
      String  :extension
      Float   :cost_usd, default: 0.0
      DateTime :recorded_at
    end
  end

  after(:all) do
    @db.drop_table(:metering_records) if @db.table_exists?(:metering_records)
  end

  let(:db) { @db }

  let(:test_app) do
    database = db
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      error do
        content_type :json
        err = env['sinatra.error']
        status 500
        Legion::JSON.dump({ error: { code: 'internal_error', message: err.message } })
      end

      helpers do
        define_method(:metering_available?) { true }
        define_method(:metering_records) { database[:metering_records] }
      end

      register Legion::API::Routes::Costs
    end
  end

  def app
    test_app
  end

  describe 'GET /api/costs/summary' do
    before do
      db[:metering_records].delete
      db[:metering_records].insert(worker_id: 'w-1', extension: 'lex-http', cost_usd: 0.05,
                                   recorded_at: Time.now.utc)
      db[:metering_records].insert(worker_id: 'w-2', extension: 'lex-vault', cost_usd: 0.10,
                                   recorded_at: Time.now.utc)
    end

    it 'returns 200 with cost summary' do
      get '/api/costs/summary'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:today)
      expect(body[:data]).to have_key(:week)
      expect(body[:data]).to have_key(:month)
      expect(body[:data][:workers]).to eq(2)
      expect(body[:data][:today]).to eq(0.15)
    end

    it 'accepts period parameter' do
      get '/api/costs/summary?period=week'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:period]).to eq('week')
    end
  end

  describe 'GET /api/costs/workers' do
    before do
      db[:metering_records].delete
      db[:metering_records].insert(worker_id: 'w-1', cost_usd: 0.50, recorded_at: Time.now.utc)
      db[:metering_records].insert(worker_id: 'w-1', cost_usd: 0.30, recorded_at: Time.now.utc)
      db[:metering_records].insert(worker_id: 'w-2', cost_usd: 0.10, recorded_at: Time.now.utc)
    end

    it 'returns 200 with worker costs sorted by total' do
      get '/api/costs/workers'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].size).to eq(2)
      expect(body[:data].first[:worker_id]).to eq('w-1')
      expect(body[:data].first[:total_cost]).to eq(0.8)
    end

    it 'respects limit parameter' do
      get '/api/costs/workers?limit=1'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data].size).to eq(1)
    end
  end

  describe 'GET /api/costs/extensions' do
    before do
      db[:metering_records].delete
      db[:metering_records].insert(extension: 'lex-http', cost_usd: 1.0, recorded_at: Time.now.utc)
      db[:metering_records].insert(extension: 'lex-http', cost_usd: 0.5, recorded_at: Time.now.utc)
      db[:metering_records].insert(extension: 'lex-vault', cost_usd: 0.2, recorded_at: Time.now.utc)
      db[:metering_records].insert(extension: nil, cost_usd: 0.1, recorded_at: Time.now.utc)
    end

    it 'returns 200 with extension costs excluding nil' do
      get '/api/costs/extensions'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].size).to eq(2)
      expect(body[:data].first[:extension]).to eq('lex-http')
    end
  end

  describe 'when data is unavailable' do
    let(:test_app) do
      Class.new(Sinatra::Base) do
        helpers Legion::API::Helpers

        set :show_exceptions, false
        set :raise_errors, false
        set :host_authorization, permitted: :any

        helpers do
          define_method(:metering_available?) { false }
        end

        register Legion::API::Routes::Costs
      end
    end

    it 'returns 503 for summary' do
      get '/api/costs/summary'
      expect(last_response.status).to eq(503)
    end

    it 'returns 503 for workers' do
      get '/api/costs/workers'
      expect(last_response.status).to eq(503)
    end

    it 'returns 503 for extensions' do
      get '/api/costs/extensions'
      expect(last_response.status).to eq(503)
    end
  end
end
