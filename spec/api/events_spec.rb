# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Events API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/events/recent' do
    it 'returns recent events as an array' do
      get '/api/events/recent'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end

    it 'respects count parameter' do
      get '/api/events/recent?count=5'
      expect(last_response.status).to eq(200)
    end
  end
end
