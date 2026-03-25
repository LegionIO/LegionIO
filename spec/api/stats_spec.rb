# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Stats API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/stats' do
    it 'returns 200 with all subsystem sections' do
      get '/api/stats'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:extensions)
      expect(body[:data]).to have_key(:gaia)
      expect(body[:data]).to have_key(:transport)
      expect(body[:data]).to have_key(:cache)
      expect(body[:data]).to have_key(:cache_local)
      expect(body[:data]).to have_key(:llm)
      expect(body[:data]).to have_key(:data)
      expect(body[:data]).to have_key(:data_local)
      expect(body[:data]).to have_key(:api)
      expect(body[:meta]).to have_key(:timestamp)
    end

    it 'returns extension counts' do
      get '/api/stats'
      body = Legion::JSON.load(last_response.body)
      ext = body[:data][:extensions]
      %i[loaded discovered subscription every poll once loop running].each do |key|
        expect(ext).to have_key(key)
      end
    end

    it 'returns api section with port and routes' do
      get '/api/stats'
      body = Legion::JSON.load(last_response.body)
      api = body[:data][:api]
      expect(api).to have_key(:port)
      expect(api).to have_key(:routes)
    end

    it 'isolates subsystem errors without failing the response' do
      allow(Legion::Extensions).to receive(:instance_variable_get).and_raise(RuntimeError, 'extensions boom')

      get '/api/stats'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:extensions][:error]).to eq('extensions boom')
      # Other sections still populated
      expect(body[:data][:api]).to have_key(:port)
    end
  end
end
