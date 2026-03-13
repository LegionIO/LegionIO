# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Extensions API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/extensions' do
    it 'returns 503 when data is not connected' do
      get '/api/extensions'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/extensions/:id' do
    it 'returns 503 when data is not connected' do
      get '/api/extensions/1'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'POST /api/extensions/:id/runners/:rid/functions/:fid/invoke' do
    it 'returns 503 when data is not connected' do
      post '/api/extensions/1/runners/1/functions/1/invoke', '{}', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
    end
  end
end
