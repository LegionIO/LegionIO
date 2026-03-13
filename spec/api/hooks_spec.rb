# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Hooks API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/hooks' do
    it 'returns list of registered hooks' do
      get '/api/hooks'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end
  end

  describe 'POST /api/hooks/:lex_name' do
    it 'returns 404 for unregistered hook' do
      post '/api/hooks/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end
end
