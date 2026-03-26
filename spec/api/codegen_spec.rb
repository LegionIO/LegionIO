# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Codegen API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/codegen/status' do
    it 'returns 503 when codegen subsystem is unavailable' do
      get '/api/codegen/status'
      expect(last_response.status).to eq(503)
      body = Legion::JSON.load(last_response.body)
      expect(body).to have_key(:error)
    end
  end

  describe 'GET /api/codegen/generated' do
    it 'returns 503 when codegen registry is unavailable' do
      get '/api/codegen/generated'
      expect(last_response.status).to eq(503)
      body = Legion::JSON.load(last_response.body)
      expect(body).to have_key(:error)
    end
  end

  describe 'GET /api/codegen/gaps' do
    it 'returns detected gaps' do
      get '/api/codegen/gaps'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /api/codegen/cycle' do
    it 'triggers a cycle' do
      post '/api/codegen/cycle'
      expect(last_response.status).to eq(200)
    end
  end
end
