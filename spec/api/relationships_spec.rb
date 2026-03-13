# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Relationships API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/relationships' do
    it 'returns 503 when data is not connected' do
      get '/api/relationships'
      expect(last_response.status).to eq(503)
    end
  end
end
