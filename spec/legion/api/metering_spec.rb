# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'sequel'
require 'legion/api/helpers'
require 'legion/api/metering'

RSpec.describe 'Metering API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))

    @db = Sequel.sqlite
    @db.create_table(:metering_records) do
      primary_key :id
      Integer :total_tokens
      Float :cost_usd
      String :model_id
      Integer :latency_ms
    end
  end

  after(:all) do
    @db.drop_table(:metering_records) if @db.table_exists?(:metering_records)
  end

  let(:db) { @db }

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      helpers do
        define_method(:require_metering!) { true }
        define_method(:metering_table?) { true }
      end

      register Legion::API::Routes::Metering
    end
  end

  def app
    test_app
  end

  describe 'GET /api/metering' do
    before do
      database = db
      data_stub = Module.new do
        define_singleton_method(:connected?) { true }
        define_singleton_method(:connection) { database }
      end
      stub_const('Legion::Data', data_stub)
      stub_const('Legion::Extensions::Metering::Runners::Metering', Module.new)
      db[:metering_records].delete
      db[:metering_records].insert(total_tokens: 120, cost_usd: 0.25)
      db[:metering_records].insert(total_tokens: 30, cost_usd: 0.05)
    end

    it 'returns dashboard headline totals' do
      get '/api/metering'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to include(
        total_cost_usd: 0.3,
        total_tokens:   150,
        total_requests: 2
      )
    end
  end
end
