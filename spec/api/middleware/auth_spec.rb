# frozen_string_literal: true

require_relative '../api_spec_helper'

unless defined?(Legion::Crypt::JWT)
  module Legion
    module Crypt
      module JWT
        class Error < StandardError; end
        class InvalidTokenError < Error; end
        class ExpiredTokenError < Error; end

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

  describe 'Negotiate/SPNEGO (Kerberos)' do
    subject(:middleware) { build_middleware(enabled: true, signing_key: signing_key) }

    let(:kerberos_claims) { { sub: 'kuser@REALM.EXAMPLE.COM', scope: 'kerberos' } }
    let(:auth_result_success) do
      { success: true, principal: 'kuser@REALM.EXAMPLE.COM', groups: ['grid-admins'], output_token: 'servertoken456' }
    end
    let(:auth_result_no_output_token) do
      { success: true, principal: 'kuser@REALM.EXAMPLE.COM', groups: [], output_token: nil }
    end

    before do
      stub_const('Legion::Extensions::Kerberos::Client', Class.new do
        def authenticate(**_kwargs); end
      end)
      stub_const('Legion::Rbac::KerberosClaimsMapper', Module.new do
        def self.map_with_fallback(**_kwargs); end
      end)
    end

    context 'when Kerberos is available and auth succeeds' do
      before do
        allow(Legion::Extensions::Kerberos::Client).to receive(:new).and_return(
          instance_double('Legion::Extensions::Kerberos::Client', authenticate: auth_result_success)
        )
        allow(Legion::Rbac::KerberosClaimsMapper).to receive(:map_with_fallback).and_return(kerberos_claims)
      end

      it 'passes through to the app (returns 200)' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it 'sets legion.auth_method to kerberos' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        middleware.call(env)
        expect(env['legion.auth_method']).to eq('kerberos')
      end

      it 'sets legion.auth to the mapped claims' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        middleware.call(env)
        expect(env['legion.auth']).to eq(kerberos_claims)
      end

      it 'sets legion.owner_msid from claims[:sub]' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        middleware.call(env)
        expect(env['legion.owner_msid']).to eq('kuser@REALM.EXAMPLE.COM')
      end

      it 'adds WWW-Authenticate response header with output token' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        _status, headers, = middleware.call(env)
        expect(headers['WWW-Authenticate']).to eq('Negotiate servertoken456')
      end

      it 'omits WWW-Authenticate header when output_token is nil' do
        allow(Legion::Extensions::Kerberos::Client).to receive(:new).and_return(
          instance_double('Legion::Extensions::Kerberos::Client', authenticate: auth_result_no_output_token)
        )
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        _status, headers, = middleware.call(env)
        expect(headers['WWW-Authenticate']).to be_nil
      end

      it 'passes principal and groups to KerberosClaimsMapper' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate dGVzdHRva2Vu' })
        middleware.call(env)
        expect(Legion::Rbac::KerberosClaimsMapper).to have_received(:map_with_fallback).with(
          hash_including(principal: 'kuser@REALM.EXAMPLE.COM', groups: ['grid-admins'])
        )
      end

      it 'accepts Negotiate with mixed case prefix' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'NEGOTIATE dGVzdHRva2Vu' })
        status, = middleware.call(env)
        expect(status).to eq(200)
      end
    end

    context 'when Kerberos is available but authenticate returns success: false' do
      before do
        allow(Legion::Extensions::Kerberos::Client).to receive(:new).and_return(
          instance_double('Legion::Extensions::Kerberos::Client',
                          authenticate: { success: false, principal: nil, groups: [], output_token: nil })
        )
      end

      it 'returns 401 with Kerberos authentication failed' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate badtoken' })
        status, _headers, body = middleware.call(env)
        expect(status).to eq(401)
        parsed = Legion::JSON.load(body.first)
        expect(parsed[:error][:message]).to eq('Kerberos authentication failed')
      end
    end

    context 'when Kerberos is available but verify_negotiate raises an exception' do
      before do
        allow(Legion::Extensions::Kerberos::Client).to receive(:new).and_return(
          instance_double('Legion::Extensions::Kerberos::Client').tap do |d|
            allow(d).to receive(:authenticate).and_raise(StandardError, 'GSSAPI error')
          end
        )
      end

      it 'returns 401 with Kerberos authentication failed' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate errortoken' })
        status, _headers, body = middleware.call(env)
        expect(status).to eq(401)
        parsed = Legion::JSON.load(body.first)
        expect(parsed[:error][:message]).to eq('Kerberos authentication failed')
      end
    end

    context 'when lex-kerberos is not loaded (kerberos_available? is false)' do
      before do
        hide_const('Legion::Extensions::Kerberos::Client')
        hide_const('Legion::Rbac::KerberosClaimsMapper')
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
      end

      it 'falls through to Bearer JWT check' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate sometoken' })
        status, = middleware.call(env)
        # Negotiate header present but lex-kerberos not loaded -> falls through ->
        # Bearer check finds no Bearer token -> 401 missing Authorization header
        expect(status).to eq(401)
      end

      it 'does not call KerberosClaimsMapper' do
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Negotiate sometoken' })
        middleware.call(env)
        # No error = mapper was not called (it's hidden)
      end

      it 'allows a subsequent Bearer token to authenticate normally' do
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
        env = make_env(path: '/api/tasks', headers: { 'HTTP_AUTHORIZATION' => 'Bearer valid.token' })
        status, = middleware.call(env)
        expect(status).to eq(200)
        expect(env['legion.auth_method']).to eq('jwt')
      end
    end

    context 'skip paths' do
      it 'passes through /api/auth/negotiate without a token' do
        env = make_env(path: '/api/auth/negotiate')
        status, = middleware.call(env)
        expect(status).to eq(200)
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
