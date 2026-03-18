# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/api/token'
require 'legion/api/auth_kerberos'

# Stub Legion::Extensions::Kerberos::Client if not loaded
unless defined?(Legion::Extensions::Kerberos::Client)
  module Legion
    module Extensions
      module Kerberos
        class Client
          def authenticate(token:); end
        end
      end
    end
  end
end

# Stub Legion::Rbac::KerberosClaimsMapper if not loaded
unless defined?(Legion::Rbac::KerberosClaimsMapper)
  module Legion
    module Rbac
      module KerberosClaimsMapper
        module_function

        def map_with_fallback(principal:, groups: [], role_map: {}, **) # rubocop:disable Lint/UnusedMethodArgument
          { sub: principal, name: principal, roles: ['worker'], scope: 'human' }
        end
      end
    end
  end
end

RSpec.describe 'GET /api/auth/negotiate' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:mock_client) { instance_double(Legion::Extensions::Kerberos::Client) }

  let(:successful_auth_result) do
    {
      success:      true,
      principal:    'user@EXAMPLE.COM',
      groups:       ['legion-admins'],
      output_token: 'server-output-token-base64'
    }
  end

  let(:mapped_claims) do
    { sub: 'user@EXAMPLE.COM', name: 'user@EXAMPLE.COM', roles: ['admin'], scope: 'human' }
  end

  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Extensions::Kerberos::Client).to receive(:new).and_return(mock_client)
    allow(Legion::Rbac::KerberosClaimsMapper).to receive(:map_with_fallback).and_return(mapped_claims)
    allow(Legion::API::Token).to receive(:issue_human_token).and_return('legion-kerberos-jwt')
  end

  context 'without Authorization header' do
    it 'returns 401 with WWW-Authenticate: Negotiate' do
      get '/api/auth/negotiate'
      expect(last_response.status).to eq(401)
      expect(last_response.headers['WWW-Authenticate']).to eq('Negotiate')
    end

    it 'returns an error body' do
      get '/api/auth/negotiate'
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('negotiate_required')
    end
  end

  context 'without Negotiate scheme (Bearer token present)' do
    it 'returns 401 with WWW-Authenticate: Negotiate' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Bearer some-jwt'
      expect(last_response.status).to eq(401)
      expect(last_response.headers['WWW-Authenticate']).to eq('Negotiate')
    end
  end

  context 'with a valid Negotiate token' do
    before do
      allow(mock_client).to receive(:authenticate).and_return(successful_auth_result)
    end

    it 'returns 200 with token, principal, roles, and auth_method' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate valid-spnego-token'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:token]).to eq('legion-kerberos-jwt')
      expect(body[:data][:principal]).to eq('user@EXAMPLE.COM')
      expect(body[:data][:roles]).to eq(['admin'])
      expect(body[:data][:auth_method]).to eq('kerberos')
    end

    it 'passes the token from the header to authenticate' do
      expect(mock_client).to receive(:authenticate).with(token: 'valid-spnego-token')
                                                   .and_return(successful_auth_result)
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate valid-spnego-token'
    end

    it 'includes WWW-Authenticate header with output_token for mutual auth' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate valid-spnego-token'
      expect(last_response.headers['WWW-Authenticate']).to eq('Negotiate server-output-token-base64')
    end

    it 'issues a human token with mapped principal and roles' do
      expect(Legion::API::Token).to receive(:issue_human_token).with(
        hash_including(msid: 'user@EXAMPLE.COM', roles: ['admin'])
      ).and_return('legion-kerberos-jwt')
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate valid-spnego-token'
    end
  end

  context 'with an invalid Negotiate token' do
    before do
      allow(mock_client).to receive(:authenticate).and_return({ success: false })
    end

    it 'returns 401' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate invalid-token'
      expect(last_response.status).to eq(401)
    end

    it 'returns WWW-Authenticate: Negotiate on failure' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate invalid-token'
      expect(last_response.headers['WWW-Authenticate']).to eq('Negotiate')
    end

    it 'returns an auth_failed error code' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate invalid-token'
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('kerberos_auth_failed')
    end
  end

  context 'when authenticate raises an exception' do
    before do
      allow(mock_client).to receive(:authenticate).and_raise(StandardError, 'GSSAPI error')
    end

    it 'returns 401' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate bad-token'
      expect(last_response.status).to eq(401)
    end
  end

  context 'when output_token is nil (no mutual auth)' do
    before do
      result = successful_auth_result.merge(output_token: nil)
      allow(mock_client).to receive(:authenticate).and_return(result)
    end

    it 'returns 200 without WWW-Authenticate in response' do
      get '/api/auth/negotiate', {}, 'HTTP_AUTHORIZATION' => 'Negotiate valid-spnego-token'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['WWW-Authenticate']).to be_nil
    end
  end
end
