# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Health and Readiness API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/health' do
    it 'returns ok status' do
      get '/api/health'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('ok')
      expect(body[:data][:version]).to eq(Legion::VERSION)
    end
  end

  describe 'GET /api/ready' do
    it 'returns readiness with component status' do
      get '/api/ready'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:ready)
      expect(body[:data]).to have_key(:components)
    end
  end
end
