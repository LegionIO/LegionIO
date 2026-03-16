# frozen_string_literal: true

require_relative '../api_spec_helper'

unless defined?(Legion::Crypt::JWT)
  module Legion
    module Crypt
      module JWT
        class InvalidTokenError < StandardError; end
        class ExpiredTokenError < StandardError; end

        def self.verify(...) = nil
      end
    end
  end
end

RSpec.describe Legion::API::Middleware::Auth do
  let(:ok_app) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:signing_key) { 'test-secret-key' }
  let(:valid_claims) { { sub: 'user123', worker_id: 'w1', scope: 'worker' } }

  def build_middleware(opts = {})
    described_class.new(ok_app, opts)
  end

  def make_env(path: '/api/tasks', headers: {})
    env = Rack::MockRequest.env_for(path)
    headers.each { |k, v| env[k] = v }
    env
  end

  describe 'when disabled (default)' do
    subject(:middleware) { build_middleware }

    it 'passes through all requests without inspecting headers' do
      env = make_env(path: '/api/tasks')
      status, = middleware.call(env)
      expect(status).to eq(200)
    end

    it 'passes through requests with no Authorization header' do
      env = make_env(path: '/api/sensitive')
      status, = middleware.call(env)
      expect(status).to eq(200)
    end
  end

  describe 'when enabled' do
    subject(:middleware) { build_middleware(enabled: true, signing_key: signing_key) }

    describe 'skip paths' do
      it 'passes through /api/health without a token' do
        env = make_env(path: '/api/health')
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it 'passes through /api/ready without a token' do
        env = make_env(path: '/api/ready')
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it 'passes through paths that start with /api/health (e.g. /api/health/live)' do
        env = make_env(path: '/api/health/live')
        status, = middleware.call(env)
        expect(status).to eq(200)
      end
    end

    describe 'missing Authorization header' do
      it 'returns 401' do
        env = make_env(path: '/api/tasks')
        status, = middleware.call(env)
        expect(status).to eq(401)
      end

      it 'returns JSON error body' do
        env = make_env(path: '/api/tasks')
        status, headers, body = middleware.call(env)
        expect(status).to eq(401)
        expect(headers['content-type']).to eq('application/json')
        parsed = Legion::JSON.load(body.first)
        expect(parsed[:error][:code]).to eq(401)
        expect(parsed[:error][:message]).to eq('missing Authorization header')
      end
    end

    describe 'invalid or expired token' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify).and_raise(Legion::Crypt::JWT::InvalidTokenError, 'bad sig')
      end

      it 'returns 401' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer bad.token.here' })
        status, = middleware.call(env)
        expect(status).to eq(401)
      end

      it 'returns JSON body with invalid or expired token message' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer bad.token.here' })
        _status, _headers, body = middleware.call(env)
        parsed = Legion::JSON.load(body.first)
        expect(parsed[:error][:message]).to eq('invalid or expired token')
      end
    end

    describe 'expired token' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify).and_raise(Legion::Crypt::JWT::ExpiredTokenError, 'expired')
      end

      it 'returns 401' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer expired.token' })
        status, = middleware.call(env)
        expect(status).to eq(401)
      end
    end

    describe 'valid token' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
      end

      it 'passes through to the app (returns 200)' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid.token.here' })
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it 'sets legion.auth in env with the claims hash' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid.token.here' })
        middleware.call(env)
        expect(env['legion.auth']).to eq(valid_claims)
      end

      it 'sets legion.worker_id from claims' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid.token.here' })
        middleware.call(env)
        expect(env['legion.worker_id']).to eq('w1')
      end

      it 'sets legion.owner_msid from sub claim' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid.token.here' })
        middleware.call(env)
        expect(env['legion.owner_msid']).to eq('user123')
      end

      it 'passes the token to JWT.verify with the configured signing key' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer mytoken' })
        middleware.call(env)
        expect(Legion::Crypt::JWT).to have_received(:verify).with('mytoken', verification_key: signing_key)
      end
    end

    describe 'Bearer token extraction' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
      end

      it 'accepts Bearer with mixed case prefix' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'BEARER mytoken' })
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it 'rejects a non-Bearer scheme (e.g. Basic)' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Basic dXNlcjpwYXNz' })
        status, = middleware.call(env)
        expect(status).to eq(401)
        _s, _h, body = middleware.call(env)
        parsed = Legion::JSON.load(body.first)
        expect(parsed[:error][:message]).to eq('missing Authorization header')
      end
    end
  end

  describe 'owner_msid fallback' do
    subject(:middleware) { build_middleware(enabled: true, signing_key: signing_key) }

    it 'falls back to owner_msid key when sub is absent' do
      claims_no_sub = { owner_msid: 'fallback_user', worker_id: 'w2', scope: 'worker' }
      allow(Legion::Crypt::JWT).to receive(:verify).and_return(claims_no_sub)
      env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer token' })
      middleware.call(env)
      expect(env['legion.owner_msid']).to eq('fallback_user')
    end
  end
end
