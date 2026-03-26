# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Codegen API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/codegen/status' do
    it 'returns codegen status' do
      get '/api/codegen/status'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body).to have_key(:data)
    end
  end

  describe 'GET /api/codegen/generated' do
    it 'returns generated functions list' do
      get '/api/codegen/generated'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body).to have_key(:data)
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
