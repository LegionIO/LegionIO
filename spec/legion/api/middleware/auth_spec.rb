# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/middleware/auth'

RSpec.describe Legion::API::Middleware::Auth do
  include Rack::Test::Methods

  let(:inner_app) do
    ->(_env) { [200, { 'content-type' => 'text/plain' }, ['OK']] }
  end

  let(:signing_key) { 'test-secret-key-32bytes-long!!' }
  let(:api_keys) { { 'valid-key-123' => { worker_id: 'w-1', owner_msid: 'user@test' } } }

  let(:app) do
    described_class.new(inner_app, enabled: true, signing_key: signing_key, api_keys: api_keys)
  end

  describe 'when auth is disabled' do
    let(:app) { described_class.new(inner_app, enabled: false) }

    it 'passes all requests through' do
      status, = app.call(Rack::MockRequest.env_for('/api/tasks'))
      expect(status).to eq(200)
    end
  end

  describe 'skip paths' do
    it 'skips /api/health' do
      status, = app.call(Rack::MockRequest.env_for('/api/health'))
      expect(status).to eq(200)
    end

    it 'skips /api/ready' do
      status, = app.call(Rack::MockRequest.env_for('/api/ready'))
      expect(status).to eq(200)
    end

    it 'skips /api/openapi.json' do
      status, = app.call(Rack::MockRequest.env_for('/api/openapi.json'))
      expect(status).to eq(200)
    end

    it 'skips /metrics' do
      status, = app.call(Rack::MockRequest.env_for('/metrics'))
      expect(status).to eq(200)
    end

    it 'skips /api/auth/token' do
      status, = app.call(Rack::MockRequest.env_for('/api/auth/token'))
      expect(status).to eq(200)
    end
  end

  describe 'missing auth' do
    it 'returns 401 for requests without auth' do
      status, headers, body = app.call(Rack::MockRequest.env_for('/api/tasks'))
      expect(status).to eq(401)
      expect(headers['content-type']).to eq('application/json')
      parsed = Legion::JSON.load(body.first)
      expect(parsed[:error][:message]).to include('missing Authorization')
    end
  end

  describe 'Bearer JWT auth' do
    before do
      jwt_error = Class.new(StandardError)
      jwt_mod = Module.new do
        define_method(:verify) do |token, verification_key:|
          return { worker_id: 'w-1', sub: 'user@test' } if token == 'valid-jwt' && verification_key

          raise jwt_error, 'invalid token'
        end

        module_function :verify
      end
      jwt_mod.const_set(:Error, jwt_error)
      stub_const('Legion::Crypt::JWT', jwt_mod)
    end

    it 'authenticates valid JWT token' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_AUTHORIZATION' => 'Bearer valid-jwt')
      status, = app.call(env)
      expect(status).to eq(200)
    end

    it 'sets auth env vars on valid JWT' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_AUTHORIZATION' => 'Bearer valid-jwt')
      inner = lambda do |e|
        expect(e['legion.auth_method']).to eq('jwt')
        expect(e['legion.worker_id']).to eq('w-1')
        [200, {}, ['OK']]
      end
      auth = described_class.new(inner, enabled: true, signing_key: signing_key)
      auth.call(env)
    end

    it 'returns 401 for invalid JWT' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_AUTHORIZATION' => 'Bearer bad-token')
      status, = app.call(env)
      expect(status).to eq(401)
    end
  end

  describe 'API key auth' do
    it 'authenticates valid API key' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_API_KEY' => 'valid-key-123')
      status, = app.call(env)
      expect(status).to eq(200)
    end

    it 'sets auth env vars on valid API key' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_API_KEY' => 'valid-key-123')
      inner = lambda do |e|
        expect(e['legion.auth_method']).to eq('api_key')
        expect(e['legion.worker_id']).to eq('w-1')
        [200, {}, ['OK']]
      end
      auth = described_class.new(inner, enabled: true, api_keys: api_keys)
      auth.call(env)
    end

    it 'returns 401 for invalid API key' do
      env = Rack::MockRequest.env_for('/api/tasks', 'HTTP_X_API_KEY' => 'bad-key')
      status, = app.call(env)
      expect(status).to eq(401)
    end
  end

  describe 'auth priority' do
    before do
      jwt_error = Class.new(StandardError)
      jwt_mod = Module.new do
        define_method(:verify) do |token, verification_key:|
          return { worker_id: 'jwt-worker', sub: 'jwt-user' } if token == 'valid-jwt' && verification_key

          raise jwt_error, 'invalid'
        end

        module_function :verify
      end
      jwt_mod.const_set(:Error, jwt_error)
      stub_const('Legion::Crypt::JWT', jwt_mod)
    end

    it 'prefers JWT over API key when both provided' do
      env = Rack::MockRequest.env_for(
        '/api/tasks',
        'HTTP_AUTHORIZATION' => 'Bearer valid-jwt',
        'HTTP_X_API_KEY'     => 'valid-key-123'
      )
      inner = lambda do |e|
        expect(e['legion.auth_method']).to eq('jwt')
        [200, {}, ['OK']]
      end
      auth = described_class.new(inner, enabled: true, signing_key: signing_key, api_keys: api_keys)
      auth.call(env)
    end
  end

  describe 'unauthorized response format' do
    it 'returns JSON error body' do
      _, _, body = app.call(Rack::MockRequest.env_for('/api/tasks'))
      parsed = Legion::JSON.load(body.first)
      expect(parsed[:error]).to have_key(:code)
      expect(parsed[:error]).to have_key(:message)
      expect(parsed[:meta]).to have_key(:timestamp)
    end
  end
end
