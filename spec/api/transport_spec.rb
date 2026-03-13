# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Transport API' do
  include Rack::Test::Methods

  def app = Legion::API

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'status' do
    it 'GET /api/transport returns connection status' do
      get '/api/transport'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      %i[connected session_open channel_open connector].each do |key|
        expect(body[:data]).to have_key(key)
      end
    end
  end

  describe 'discovery' do
    it 'GET /api/transport/exchanges returns exchange list' do
      get '/api/transport/exchanges'
      expect(last_response.status).to eq(200)
      expect(Legion::JSON.load(last_response.body)[:data]).to be_an(Array)
    end

    it 'GET /api/transport/queues returns queue list' do
      get '/api/transport/queues'
      expect(last_response.status).to eq(200)
      expect(Legion::JSON.load(last_response.body)[:data]).to be_an(Array)
    end
  end

  describe 'publish' do
    it 'requires exchange field' do
      post '/api/transport/publish', Legion::JSON.dump({ routing_key: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      expect(Legion::JSON.load(last_response.body)[:error][:message]).to include('exchange')
    end

    it 'requires routing_key field' do
      post '/api/transport/publish', Legion::JSON.dump({ exchange: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      expect(Legion::JSON.load(last_response.body)[:error][:message]).to include('routing_key')
    end
  end
end
