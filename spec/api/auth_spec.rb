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

RSpec.describe 'Auth API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:valid_body) do
    {
      grant_type:    'urn:ietf:params:oauth:grant-type:token-exchange',
      subject_token: 'entra-jwt-token'
    }
  end

  let(:entra_claims) do
    { oid: 'user-oid', name: 'Jane Doe', tid: 'tenant-1',
      roles: ['Legion.Supervisor'], groups: [] }
  end

  let(:rbac_entra_settings) do
    {
      tenant_id:    'tenant-1',
      role_map:     Legion::Rbac::EntraClaimsMapper::DEFAULT_ROLE_MAP,
      group_map:    {},
      default_role: 'worker'
    }
  end

  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    rbac_hash = { entra: rbac_entra_settings }
    allow(Legion::Settings).to receive(:[]).with(:rbac).and_return(rbac_hash)
  end

  describe 'POST /api/auth/token' do
    context 'with valid Entra token' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify_with_jwks).and_return(entra_claims)
        allow(Legion::API::Token).to receive(:issue_human_token).and_return('legion-jwt-123')
      end

      it 'returns a Legion access token' do
        post '/api/auth/token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:access_token]).to eq('legion-jwt-123')
        expect(body[:data][:token_type]).to eq('Bearer')
        expect(body[:data][:roles]).to eq(['supervisor'])
      end

      it 'issues token with mapped roles' do
        expect(Legion::API::Token).to receive(:issue_human_token).with(
          hash_including(msid: 'user-oid', roles: ['supervisor'])
        ).and_return('legion-jwt-123')
        post '/api/auth/token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
      end
    end

    context 'with expired Entra token' do
      before do
        allow(Legion::Crypt::JWT).to receive(:verify_with_jwks)
          .and_raise(Legion::Crypt::JWT::ExpiredTokenError, 'token has expired')
      end

      it 'returns 401' do
        post '/api/auth/token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(401)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('token_expired')
      end
    end

    context 'with invalid grant_type' do
      it 'returns 400' do
        body = valid_body.merge(grant_type: 'authorization_code')
        post '/api/auth/token', Legion::JSON.dump(body), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
      end
    end

    context 'with missing subject_token' do
      it 'returns 400' do
        body = valid_body.except(:subject_token)
        post '/api/auth/token', Legion::JSON.dump(body), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
      end
    end

    context 'with no tenant configured' do
      let(:rbac_entra_settings) { { tenant_id: nil } }

      before do
        allow(Legion::Crypt::JWT).to receive(:verify_with_jwks)
      end

      it 'returns 500' do
        post '/api/auth/token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(500)
      end
    end
  end
end
