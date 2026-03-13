# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Nodes API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/nodes' do
    it 'returns 503 when data is not connected' do
      get '/api/nodes'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/nodes/:id' do
    it 'returns 503 when data is not connected' do
      get '/api/nodes/1'
      expect(last_response.status).to eq(503)
    end
  end
end
