# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/traces'

RSpec.describe 'Traces API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
  end

  let(:test_app) do
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

      register Legion::API::Routes::Traces
    end
  end

  def app
    test_app
  end

  describe 'POST /api/traces/search' do
    context 'when LLM is not available' do
      before do
        hide_const('Legion::LLM')
      end

      it 'returns 503' do
        post '/api/traces/search', Legion::JSON.dump({ query: 'test' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('trace_search_unavailable')
      end
    end

    context 'when TraceSearch is available' do
      before do
        stub_const('Legion::LLM', Module.new)
        trace_mod = Module.new do
          def self.search(*, **)
            { results: [{ id: 1, status: 'success' }], count: 1, total: 1, truncated: false, filter: {} }
          end

          def self.summarize(*)
            { total_records: 10 }
          end

          def self.detect_anomalies(**)
            { anomalies: [], recent_count: 5, baseline_count: 50 }
          end
        end
        stub_const('Legion::TraceSearch', trace_mod)
      end

      it 'returns 422 when query is missing' do
        post '/api/traces/search', Legion::JSON.dump({}), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('missing_field')
      end

      it 'returns search results' do
        post '/api/traces/search', Legion::JSON.dump({ query: 'failed tasks' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:results]).to be_an(Array)
        expect(body[:data][:count]).to eq(1)
      end

      it 'passes custom limit' do
        allow(Legion::TraceSearch).to receive(:search).with('test', limit: 10).and_return(
          { results: [], count: 0, total: 0, truncated: false, filter: {} }
        )
        post '/api/traces/search', Legion::JSON.dump({ query: 'test', limit: 10 }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'POST /api/traces/summary' do
    context 'when LLM is not available' do
      before do
        hide_const('Legion::LLM')
      end

      it 'returns 503' do
        post '/api/traces/summary', Legion::JSON.dump({ query: 'test' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when TraceSearch is available' do
      before do
        stub_const('Legion::LLM', Module.new)
        trace_mod = Module.new do
          def self.summarize(*)
            { total_records: 42, total_cost: 1.23 }
          end
        end
        stub_const('Legion::TraceSearch', trace_mod)
      end

      it 'returns 422 when query is missing' do
        post '/api/traces/summary', Legion::JSON.dump({}), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end

      it 'returns summary data' do
        post '/api/traces/summary', Legion::JSON.dump({ query: 'all tasks today' }), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:total_records]).to eq(42)
      end
    end
  end

  describe 'GET /api/traces/anomalies' do
    context 'when LLM is not available' do
      before do
        hide_const('Legion::LLM')
      end

      it 'returns 503' do
        get '/api/traces/anomalies'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when TraceSearch is available' do
      before do
        stub_const('Legion::LLM', Module.new)
        trace_mod = Module.new do
          def self.detect_anomalies(**)
            { anomalies: [], recent_count: 10, baseline_count: 100 }
          end
        end
        stub_const('Legion::TraceSearch', trace_mod)
      end

      it 'returns anomaly report' do
        get '/api/traces/anomalies'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:anomalies]).to be_an(Array)
        expect(body[:data][:recent_count]).to eq(10)
      end

      it 'accepts custom threshold' do
        allow(Legion::TraceSearch).to receive(:detect_anomalies).with(threshold: 3.5).and_return(
          { anomalies: [], recent_count: 10, baseline_count: 100 }
        )
        get '/api/traces/anomalies', threshold: '3.5'
        expect(last_response.status).to eq(200)
      end
    end
  end
end
