# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Transport API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/transport' do
    it 'returns transport connection status' do
      get '/api/transport'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:connected)
      expect(body[:data]).to have_key(:session_open)
      expect(body[:data]).to have_key(:channel_open)
      expect(body[:data]).to have_key(:connector)
    end
  end

  describe 'GET /api/transport/exchanges' do
    it 'returns exchange list' do
      get '/api/transport/exchanges'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end
  end

  describe 'GET /api/transport/queues' do
    it 'returns queue list' do
      get '/api/transport/queues'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end
  end

  describe 'POST /api/transport/publish' do
    it 'requires exchange field' do
      post '/api/transport/publish', Legion::JSON.dump({ routing_key: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:message]).to include('exchange')
    end

    it 'requires routing_key field' do
      post '/api/transport/publish', Legion::JSON.dump({ exchange: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:message]).to include('routing_key')
    end
  end
end
