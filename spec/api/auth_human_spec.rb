# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/api/token'

# Stub Legion::Rbac::EntraClaimsMapper if legion-rbac is not installed
unless defined?(Legion::Rbac::EntraClaimsMapper)
  module Legion
    module Rbac
      module EntraClaimsMapper
        DEFAULT_ROLE_MAP = {
          'Legion.Admin'      => 'admin',
          'Legion.Supervisor' => 'supervisor',
          'Legion.Worker'     => 'worker',
          'Legion.Observer'   => 'governance-observer'
        }.freeze

        module_function

        def map_claims(entra_claims, role_map: DEFAULT_ROLE_MAP, group_map: {}, default_role: 'worker') # rubocop:disable Lint/UnusedMethodArgument
          roles = []
          Array(entra_claims[:roles]).each do |r|
            roles << role_map[r] if role_map[r]
          end
          roles << default_role if roles.empty?
          { sub: entra_claims[:oid], name: entra_claims[:name], roles: roles, team: entra_claims[:tid], scope: 'human' }
        end
      end
    end
  end
end

RSpec.describe 'Human Auth Flow' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:entra_settings) do
    {
      tenant_id:     'tenant-1',
      client_id:     'legion-web-app',
      client_secret: 'test-secret',
      redirect_uri:  'http://localhost:4567/api/auth/callback',
      role_map:      Legion::Rbac::EntraClaimsMapper::DEFAULT_ROLE_MAP,
      group_map:     {},
      default_role:  'worker'
    }
  end

  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Settings).to receive(:[]).with(:rbac).and_return({ entra: entra_settings })
  end

  describe 'GET /api/auth/authorize' do
    before do
      allow(Legion::Crypt::JWT).to receive(:issue).and_return('state-token')
    end

    it 'redirects to Entra authorization endpoint' do
      get '/api/auth/authorize'
      expect(last_response.status).to eq(302)
      location = last_response.headers['Location']
      expect(location).to include('login.microsoftonline.com/tenant-1/oauth2/v2.0/authorize')
      expect(location).to include('client_id=legion-web-app')
      expect(location).to include('response_type=code')
    end
  end

  describe 'GET /api/auth/callback' do
    let(:id_token_claims) do
      { oid: 'user-oid', name: 'Jane Doe', tid: 'tenant-1',
        roles: ['Legion.Supervisor'], groups: [] }
    end

    before do
      allow(Legion::Crypt::JWT).to receive(:verify).and_return({ nonce: 'x', purpose: 'oauth_state' })
      allow(Legion::API::Routes::AuthHuman).to receive(:exchange_code)
        .and_return({ id_token: 'entra-id-token', access_token: 'entra-at' })
      allow(Legion::Crypt::JWT).to receive(:verify_with_jwks).and_return(id_token_claims)
      allow(Legion::API::Token).to receive(:issue_human_token).and_return('legion-human-jwt')
    end

    it 'exchanges code and returns Legion JWT in JSON mode' do
      get '/api/auth/callback', { code: 'auth-code', state: 'state-token' },
          'HTTP_ACCEPT' => 'application/json'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:access_token]).to eq('legion-human-jwt')
      expect(body[:data][:roles]).to eq(['supervisor'])
    end

    it 'returns 400 when code is missing' do
      get '/api/auth/callback', { state: 'state-token' }, 'HTTP_ACCEPT' => 'application/json'
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 when Entra returns an error' do
      get '/api/auth/callback', { error: 'access_denied', error_description: 'denied' },
          'HTTP_ACCEPT' => 'application/json'
      expect(last_response.status).to eq(400)
    end

    it 'validates CSRF state token' do
      allow(Legion::Crypt::JWT).to receive(:verify).with('bad-state')
                                                   .and_raise(Legion::Crypt::JWT::Error, 'invalid')
      get '/api/auth/callback', { code: 'auth-code', state: 'bad-state' },
          'HTTP_ACCEPT' => 'application/json'
      expect(last_response.status).to eq(400)
    end

    it 'redirects in browser mode' do
      get '/api/auth/callback', { code: 'auth-code', state: 'state-token' },
          'HTTP_ACCEPT' => 'text/html'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('access_token=legion-human-jwt')
    end
  end
end
