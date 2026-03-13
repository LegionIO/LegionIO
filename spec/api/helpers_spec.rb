# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe Legion::API::Helpers do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'response envelope' do
    it 'returns JSON with data and meta keys on /api/health' do
      get '/api/health'
      body = Legion::JSON.load(last_response.body)
      expect(body).to have_key(:data)
      expect(body).to have_key(:meta)
      expect(body[:meta]).to have_key(:timestamp)
      expect(body[:meta][:node]).to eq('test-node')
    end
  end

  describe 'not_found handler' do
    it 'returns 404 with error envelope for unknown routes' do
      get '/api/nonexistent'
      expect(last_response.status).to eq(404)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('not_found')
    end
  end

  describe 'require_data!' do
    it 'returns 503 when data is not connected' do
      get '/api/tasks'
      expect(last_response.status).to eq(503)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('data_unavailable')
    end
  end
end
