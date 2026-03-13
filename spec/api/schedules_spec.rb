# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Schedules API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/schedules' do
    it 'returns 503 when data is not connected' do
      get '/api/schedules'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'POST /api/schedules' do
    it 'returns 503 when data is not connected' do
      post '/api/schedules', '{}', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
    end
  end
end
