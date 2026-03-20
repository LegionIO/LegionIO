# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'ACP API routes' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /.well-known/agent.json' do
    it 'returns an agent card' do
      get '/.well-known/agent.json'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:name]).to be_a(String)
      expect(body[:protocol]).to eq('acp/1.0')
    end
  end

  describe 'POST /api/acp/tasks' do
    it 'accepts a task and returns 202' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 1, success: true })
      post '/api/acp/tasks', Legion::JSON.dump({ input: { text: 'test' } }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('queued')
    end
  end

  describe 'GET /api/acp/tasks/:id' do
    it 'returns 404 for unknown task' do
      get '/api/acp/tasks/99999'
      expect(last_response.status).to eq(404)
    end
  end
end
