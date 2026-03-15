# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Gaia API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/gaia/status' do
    context 'when Legion::Gaia is not defined' do
      it 'returns 503 with started: false' do
        get '/api/gaia/status'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:started]).to eq(false)
      end
    end

    context 'when Legion::Gaia is defined but not started' do
      before do
        gaia = Module.new do
          def self.started? = false
        end
        stub_const('Legion::Gaia', gaia)
      end

      it 'returns 503 with started: false' do
        get '/api/gaia/status'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:started]).to eq(false)
      end
    end

    context 'when Legion::Gaia is defined and started' do
      let(:gaia_status) { { started: true, version: '1.0.0', uptime: 42 } }

      before do
        status = gaia_status
        gaia = Module.new do
          define_singleton_method(:started?) { true }
          define_singleton_method(:status) { status }
        end
        stub_const('Legion::Gaia', gaia)
      end

      it 'returns 200 with gaia status data' do
        get '/api/gaia/status'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:started]).to eq(true)
        expect(body[:data][:version]).to eq('1.0.0')
        expect(body[:data][:uptime]).to eq(42)
      end

      it 'includes meta with timestamp and node' do
        get '/api/gaia/status'
        body = Legion::JSON.load(last_response.body)
        expect(body[:meta]).to have_key(:timestamp)
        expect(body[:meta][:node]).to eq('test-node')
      end
    end
  end
end
