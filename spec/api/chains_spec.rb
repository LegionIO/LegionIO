# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Chains API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/chains' do
    it 'returns 503 when data is not connected' do
      get '/api/chains'
      expect(last_response.status).to eq(503)
    end
  end
end
