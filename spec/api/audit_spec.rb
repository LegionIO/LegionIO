# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Audit API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/audit' do
    it 'returns 503 when data is not connected' do
      get '/api/audit'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/audit/verify' do
    it 'returns 503 when data is not connected' do
      get '/api/audit/verify'
      expect(last_response.status).to eq(503)
    end
  end
end
