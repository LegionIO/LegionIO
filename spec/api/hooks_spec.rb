# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Hooks API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    Legion::API.hook_registry.clear
  end

  let(:dummy_hook_class) do
    Class.new(Legion::Extensions::Hooks::Base)
  end

  let(:mounted_hook_class) do
    Class.new(Legion::Extensions::Hooks::Base)
  end

  describe 'GET /api/hooks' do
    it 'returns list of registered hooks' do
      get '/api/hooks'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end

    it 'includes route_path and endpoint in hook listing' do
      Legion::API.register_hook(
        lex_name: 'test_ext', hook_name: 'webhook',
        hook_class: dummy_hook_class, route_path: 'test_ext/webhook'
      )
      get '/api/hooks'
      body = Legion::JSON.load(last_response.body)
      hook = body[:data].first
      expect(hook[:route_path]).to eq('test_ext/webhook')
      expect(hook[:endpoint]).to eq('/api/hooks/lex/test_ext/webhook')
    end
  end

  describe 'GET /api/hooks/lex/*' do
    it 'returns 404 for unregistered hook path' do
      get '/api/hooks/lex/nonexistent/webhook'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /api/hooks/lex/*' do
    it 'returns 404 for unregistered hook path' do
      post '/api/hooks/lex/nonexistent/webhook'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'Hooks::Base.mount' do
    it 'mount DSL is removed; routes are fully derived from naming' do
      klass = Class.new(Legion::Extensions::Hooks::Base)
      expect(klass).not_to respond_to(:mount)
    end
  end

  describe 'register_hook with route_path' do
    it 'registers hook with computed route_path' do
      Legion::API.register_hook(
        lex_name: 'microsoft_teams', hook_name: 'auth',
        hook_class: mounted_hook_class, route_path: 'microsoft_teams/auth/callback'
      )
      hook = Legion::API.find_hook_by_path('microsoft_teams/auth/callback')
      expect(hook).not_to be_nil
      expect(hook[:route_path]).to eq('microsoft_teams/auth/callback')
    end

    it 'defaults route_path to lex_name/hook_name when not provided' do
      Legion::API.register_hook(
        lex_name: 'github', hook_name: 'push',
        hook_class: dummy_hook_class
      )
      hook = Legion::API.find_hook_by_path('github/push')
      expect(hook).not_to be_nil
    end
  end
end
