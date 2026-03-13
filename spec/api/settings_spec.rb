# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Settings API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/settings' do
    it 'returns settings with sensitive values redacted' do
      get '/api/settings'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_a(Hash)
    end
  end

  describe 'GET /api/settings/:key' do
    it 'returns a specific setting' do
      get '/api/settings/client'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:key]).to eq('client')
    end

    it 'returns 404 for unknown setting' do
      get '/api/settings/nonexistent_setting_xyz'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'PUT /api/settings/:key' do
    it 'rejects writes to read-only sections' do
      put '/api/settings/crypt', Legion::JSON.dump({ value: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(403)
    end

    it 'rejects writes to transport section' do
      put '/api/settings/transport', Legion::JSON.dump({ value: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(403)
    end

    it 'requires a value field' do
      put '/api/settings/test_key', Legion::JSON.dump({ other: 'field' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
    end
  end
end
