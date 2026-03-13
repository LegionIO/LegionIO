# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Tasks API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/tasks' do
    it 'returns 503 when data is not connected' do
      get '/api/tasks'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'POST /api/tasks' do
    it 'returns 422 when runner_class is missing' do
      post '/api/tasks', Legion::JSON.dump({ function: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_field')
    end

    it 'returns 422 when function is missing' do
      post '/api/tasks', Legion::JSON.dump({ runner_class: 'SomeRunner' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_field')
    end
  end

  describe 'GET /api/tasks/:id' do
    it 'returns 503 when data is not connected' do
      get '/api/tasks/1'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'DELETE /api/tasks/:id' do
    it 'returns 503 when data is not connected' do
      delete '/api/tasks/1'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/tasks/:id/logs' do
    it 'returns 503 when data is not connected' do
      get '/api/tasks/1/logs'
      expect(last_response.status).to eq(503)
    end
  end
end
