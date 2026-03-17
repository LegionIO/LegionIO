# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Capacity API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    allow(Legion::API::Routes::Capacity).to receive(:fetch_worker_list).and_return([
                                                                                     { worker_id: 'w1', status: 'active' },
                                                                                     { worker_id: 'w2', status: 'active' },
                                                                                     { worker_id: 'w3', status: 'stopped' }
                                                                                   ])
  end

  describe 'GET /api/capacity' do
    it 'returns aggregate capacity' do
      get '/api/capacity'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:active_workers]).to eq(2)
      expect(body[:data][:max_throughput_tps]).to eq(20)
    end
  end

  describe 'GET /api/capacity/forecast' do
    it 'returns forecast with default params' do
      get '/api/capacity/forecast'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:current_workers]).to eq(2)
    end

    it 'accepts custom growth rate' do
      get '/api/capacity/forecast', days: 30, growth_rate: 0.5
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:projected_workers]).to be >= 2
    end
  end

  describe 'GET /api/capacity/workers' do
    it 'returns per-worker stats' do
      get '/api/capacity/workers'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data].size).to eq(3)
    end
  end
end
