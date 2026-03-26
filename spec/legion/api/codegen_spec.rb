# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/codegen'

RSpec.describe 'Codegen API routes' do
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

      register Legion::API::Routes::Codegen
    end
  end

  def app
    test_app
  end

  describe 'GET /api/codegen/status' do
    context 'when SelfGenerate is not available' do
      before { hide_const('Legion::MCP::SelfGenerate') }

      it 'returns 503' do
        get '/api/codegen/status'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when SelfGenerate is available' do
      before do
        self_gen = Module.new do
          def self.status
            { enabled: true, last_cycle_at: '2026-03-26T00:00:00Z', gaps_detected: 5 }
          end
        end
        stub_const('Legion::MCP::SelfGenerate', self_gen)
      end

      it 'returns 200' do
        get '/api/codegen/status'
        expect(last_response.status).to eq(200)
      end

      it 'returns status data' do
        get '/api/codegen/status'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:enabled]).to eq(true)
        expect(body[:data][:gaps_detected]).to eq(5)
      end
    end
  end

  describe 'GET /api/codegen/generated' do
    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'returns 503' do
        get '/api/codegen/generated'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.list(status: nil)
            records = [
              { id: 'gen_001', name: 'fetch_weather', status: 'approved' },
              { id: 'gen_002', name: 'parse_csv', status: 'pending' }
            ]
            records = records.select { |r| r[:status] == status } if status
            records
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'returns 200 with all records' do
        get '/api/codegen/generated'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data].size).to eq(2)
      end

      it 'filters by status param' do
        get '/api/codegen/generated', status: 'approved'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data].size).to eq(1)
        expect(body[:data].first[:name]).to eq('fetch_weather')
      end
    end
  end

  describe 'GET /api/codegen/generated/:id' do
    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'returns 503' do
        get '/api/codegen/generated/gen_001'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.get(id:)
            return { id: id, name: 'fetch_weather', status: 'approved' } if id == 'gen_001'

            nil
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'returns 200 for existing record' do
        get '/api/codegen/generated/gen_001'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:name]).to eq('fetch_weather')
      end

      it 'returns 404 for missing record' do
        get '/api/codegen/generated/nonexistent'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'POST /api/codegen/generated/:id/approve' do
    context 'when ReviewHandler is not available' do
      before { hide_const('Legion::Extensions::Codegen::Runners::ReviewHandler') }

      it 'returns 503' do
        post '/api/codegen/generated/gen_001/approve'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when ReviewHandler is available' do
      before do
        handler = Module.new do
          def self.handle_verdict(review:)
            { generation_id: review[:generation_id], status: 'approved' }
          end
        end
        stub_const('Legion::Extensions::Codegen::Runners::ReviewHandler', handler)
      end

      it 'returns 200 with approval result' do
        post '/api/codegen/generated/gen_001/approve'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:status]).to eq('approved')
        expect(body[:data][:generation_id]).to eq('gen_001')
      end
    end
  end

  describe 'POST /api/codegen/generated/:id/reject' do
    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'returns 503' do
        post '/api/codegen/generated/gen_001/reject'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.update_status(id:, status:)
            { id: id, status: status }
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'returns 200 with rejected status' do
        post '/api/codegen/generated/gen_001/reject'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:id]).to eq('gen_001')
        expect(body[:data][:status]).to eq('rejected')
      end
    end
  end

  describe 'POST /api/codegen/generated/:id/retry' do
    context 'when GeneratedRegistry is not available' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'returns 503' do
        post '/api/codegen/generated/gen_001/retry'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when GeneratedRegistry is available' do
      before do
        registry = Module.new do
          def self.update_status(id:, status:)
            { id: id, status: status }
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'returns 200 with pending status' do
        post '/api/codegen/generated/gen_001/retry'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:id]).to eq('gen_001')
        expect(body[:data][:status]).to eq('pending')
      end
    end
  end

  describe 'GET /api/codegen/gaps' do
    context 'when GapDetector is available' do
      before do
        detector = Module.new do
          def self.detect_gaps
            [{ gap_id: 'gap_1', gap_type: :unmatched_intent, priority: 0.8 }]
          end
        end
        stub_const('Legion::MCP::GapDetector', detector)
      end

      it 'returns 200 with gaps' do
        get '/api/codegen/gaps'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data].size).to eq(1)
        expect(body[:data].first[:gap_id]).to eq('gap_1')
      end
    end

    context 'when GapDetector is not available' do
      before { hide_const('Legion::MCP::GapDetector') }

      it 'returns 200 with empty array' do
        get '/api/codegen/gaps'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data]).to eq([])
      end
    end
  end

  describe 'POST /api/codegen/cycle' do
    context 'when SelfGenerate is available' do
      before do
        self_gen = Module.new do
          def self.run_cycle
            { triggered: true, gaps_processed: 2 }
          end
        end
        stub_const('Legion::MCP::SelfGenerate', self_gen)
        allow(Legion::MCP::SelfGenerate).to receive(:instance_variable_set)
      end

      it 'returns 200 with cycle result' do
        post '/api/codegen/cycle'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:triggered]).to eq(true)
      end

      it 'resets cooldown before running' do
        expect(Legion::MCP::SelfGenerate).to receive(:instance_variable_set).with(:@last_cycle_at, nil)
        post '/api/codegen/cycle'
      end
    end

    context 'when SelfGenerate is not available' do
      before { hide_const('Legion::MCP::SelfGenerate') }

      it 'returns 200 with triggered false' do
        post '/api/codegen/cycle'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:triggered]).to eq(false)
      end
    end
  end
end
