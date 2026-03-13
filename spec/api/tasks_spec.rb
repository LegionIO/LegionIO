# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Tasks API' do
  include Rack::Test::Methods

  def app = Legion::API

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'collection routes' do
    it 'GET /api/tasks returns 503 when data is not connected' do
      get '/api/tasks'
      expect(last_response.status).to eq(503)
    end

    it 'POST /api/tasks returns 422 when runner_class is missing' do
      post '/api/tasks', Legion::JSON.dump({ function: 'test' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      expect(Legion::JSON.load(last_response.body)[:error][:code]).to eq('missing_field')
    end

    it 'POST /api/tasks returns 422 when function is missing' do
      post '/api/tasks', Legion::JSON.dump({ runner_class: 'SomeRunner' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      expect(Legion::JSON.load(last_response.body)[:error][:code]).to eq('missing_field')
    end
  end

  describe 'member routes' do
    it 'GET /api/tasks/:id returns 503 when data is not connected' do
      get '/api/tasks/1'
      expect(last_response.status).to eq(503)
    end

    it 'DELETE /api/tasks/:id returns 503 when data is not connected' do
      delete '/api/tasks/1'
      expect(last_response.status).to eq(503)
    end

    it 'GET /api/tasks/:id/logs returns 503 when data is not connected' do
      get '/api/tasks/1/logs'
      expect(last_response.status).to eq(503)
    end
  end
end
