# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'

# ---------------------------------------------------------------------------
# Stub the optional ruby-saml gem so specs run without it installed.
# ---------------------------------------------------------------------------
unless defined?(OneLogin::RubySaml)
  module OneLogin
    module RubySaml
      class Settings
        attr_accessor :idp_sso_service_url, :idp_cert, :sp_entity_id,
                      :assertion_consumer_service_url, :name_identifier_format

        def initialize
          @security = {}
        end

        attr_reader :security
      end

      class Metadata
        def generate(*)
          '<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata"/>'
        end
      end

      class Authrequest
        def create(_settings)
          'https://idp.example.com/saml/sso?SAMLRequest=ENCODED'
        end
      end

      class Response
        attr_reader :errors, :nameid, :attributes

        def initialize(_raw, **)
          @errors     = []
          @nameid     = 'user@example.com'
          @attributes = FakeAttributes.new
        end

        def is_valid?
          true
        end
      end

      class FakeAttributes
        def [](name)
          case name
          when 'email', 'mail', 'emailAddress',
               'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
            'user@example.com'
          when 'displayName', 'name',
               'http://schemas.microsoft.com/identity/claims/displayname',
               'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
            'Test User'
          end
        end

        def multi(name)
          return %w[group-a group-b] if name == 'groups'

          nil
        end
      end
    end
  end
end

require 'legion/api/auth_saml'

RSpec.describe 'SAML Auth API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client]     = { name: 'test-node', ready: true }
    loader.settings[:data]       = { connected: false }
    loader.settings[:transport]  = { connected: false }
    loader.settings[:extensions] = {}
    loader.settings[:auth] = {
      saml: {
        enabled:                   true,
        idp_sso_url:               'https://idp.example.com/saml/sso',
        idp_cert:                  'FAKE_CERT',
        sp_entity_id:              'https://legion.example.com/saml',
        sp_acs_url:                'https://legion.example.com/api/auth/saml/acs',
        want_assertions_signed:    false,
        want_assertions_encrypted: false,
        default_role:              'worker',
        group_map:                 {}
      }
    }
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::AuthSaml
    end
  end

  def app
    test_app
  end

  # Stub Token issuance so specs don't need legion-crypt
  before do
    token_mod = Module.new do
      def self.issue_human_token(**_kwargs)
        'stub.jwt.token'
      end
    end
    stub_const('Legion::API::Token', token_mod)
  end

  # ────────────────────────────────────────────────────────────────────────
  # GET /api/auth/saml/metadata
  # ────────────────────────────────────────────────────────────────────────

  describe 'GET /api/auth/saml/metadata' do
    it 'returns 200' do
      get '/api/auth/saml/metadata'
      expect(last_response.status).to eq(200)
    end

    it 'returns XML content type' do
      get '/api/auth/saml/metadata'
      expect(last_response.content_type).to include('xml')
    end

    it 'returns an EntityDescriptor root element' do
      get '/api/auth/saml/metadata'
      expect(last_response.body).to include('EntityDescriptor')
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # GET /api/auth/saml/login
  # ────────────────────────────────────────────────────────────────────────

  describe 'GET /api/auth/saml/login' do
    it 'redirects to IdP' do
      get '/api/auth/saml/login'
      expect(last_response.status).to eq(302)
    end

    it 'redirects to the IdP SSO URL' do
      get '/api/auth/saml/login'
      expect(last_response.location).to include('idp.example.com')
    end

    it 'includes SAMLRequest in redirect' do
      get '/api/auth/saml/login'
      expect(last_response.location).to include('SAMLRequest')
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # POST /api/auth/saml/acs — valid assertion
  # ────────────────────────────────────────────────────────────────────────

  describe 'POST /api/auth/saml/acs with a valid SAMLResponse' do
    let(:valid_params) { { 'SAMLResponse' => 'BASE64ENCODEDRESPONSE' } }

    it 'returns 200' do
      post '/api/auth/saml/acs', valid_params
      expect(last_response.status).to eq(200)
    end

    it 'returns an access_token' do
      post '/api/auth/saml/acs', valid_params
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:access_token]).to eq('stub.jwt.token')
    end

    it 'returns token_type Bearer' do
      post '/api/auth/saml/acs', valid_params
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:token_type]).to eq('Bearer')
    end

    it 'returns expires_in' do
      post '/api/auth/saml/acs', valid_params
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:expires_in]).to eq(28_800)
    end

    it 'returns roles array' do
      post '/api/auth/saml/acs', valid_params
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:roles]).to be_an(Array)
    end

    it 'returns display name' do
      post '/api/auth/saml/acs', valid_params
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('Test User')
    end

    it 'issues token with correct msid' do
      expect(Legion::API::Token).to receive(:issue_human_token).with(
        hash_including(msid: 'user@example.com')
      ).and_return('stub.jwt.token')
      post '/api/auth/saml/acs', valid_params
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # POST /api/auth/saml/acs — missing SAMLResponse
  # ────────────────────────────────────────────────────────────────────────

  describe 'POST /api/auth/saml/acs without SAMLResponse' do
    it 'returns 400' do
      post '/api/auth/saml/acs', {}
      expect(last_response.status).to eq(400)
    end

    it 'returns error code missing_saml_response' do
      post '/api/auth/saml/acs', {}
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_saml_response')
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # POST /api/auth/saml/acs — invalid assertion
  # ────────────────────────────────────────────────────────────────────────

  describe 'POST /api/auth/saml/acs with an invalid SAMLResponse' do
    before do
      invalid_response_class = Class.new do
        def initialize(_raw, **)
          @errors = ['Signature validation failed', 'Certificate expired']
        end

        def is_valid?
          false
        end

        attr_reader :errors

        def nameid
          nil
        end

        def attributes
          nil
        end
      end

      stub_const('OneLogin::RubySaml::Response', invalid_response_class)
    end

    it 'returns 401' do
      post '/api/auth/saml/acs', { 'SAMLResponse' => 'BADINPUT' }
      expect(last_response.status).to eq(401)
    end

    it 'returns error code saml_invalid' do
      post '/api/auth/saml/acs', { 'SAMLResponse' => 'BADINPUT' }
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('saml_invalid')
    end

    it 'includes validation errors in the message' do
      post '/api/auth/saml/acs', { 'SAMLResponse' => 'BADINPUT' }
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:message]).to include('Signature validation failed')
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Module-level unit tests
  # ────────────────────────────────────────────────────────────────────────

  describe 'Routes::AuthSaml.extract_claims' do
    let(:fake_response) do
      double('SamlResponse',
             nameid:     'user@example.com',
             attributes: OneLogin::RubySaml::FakeAttributes.new)
    end

    it 'extracts nameid' do
      claims = Legion::API::Routes::AuthSaml.extract_claims(fake_response)
      expect(claims[:nameid]).to eq('user@example.com')
    end

    it 'extracts email from attributes' do
      claims = Legion::API::Routes::AuthSaml.extract_claims(fake_response)
      expect(claims[:email]).to eq('user@example.com')
    end

    it 'extracts display_name from attributes' do
      claims = Legion::API::Routes::AuthSaml.extract_claims(fake_response)
      expect(claims[:display_name]).to eq('Test User')
    end

    it 'extracts groups as an array' do
      claims = Legion::API::Routes::AuthSaml.extract_claims(fake_response)
      expect(claims[:groups]).to eq(%w[group-a group-b])
    end
  end

  describe 'Routes::AuthSaml.map_roles' do
    context 'when Legion::Rbac::ClaimsMapper is not loaded' do
      it 'returns the default worker role' do
        roles = Legion::API::Routes::AuthSaml.map_roles(['some-group'])
        expect(roles).to eq(['worker'])
      end
    end

    context 'when Legion::Rbac::ClaimsMapper is available' do
      before do
        mapper = Module.new do
          def self.groups_to_roles(groups, group_map: {}, default_role: 'worker')
            groups.map { |g| group_map[g] || default_role }
          end
        end
        stub_const('Legion::Rbac::ClaimsMapper', mapper)
      end

      it 'delegates to ClaimsMapper.groups_to_roles' do
        roles = Legion::API::Routes::AuthSaml.map_roles(['admin-group'])
        expect(roles).to eq(['worker'])
      end

      it 'applies group_map when configured' do
        allow(Legion::API::Routes::AuthSaml).to receive(:resolve_saml_config).and_return(
          enabled:      true,
          group_map:    { 'admin-group' => 'admin' },
          default_role: 'worker'
        )
        roles = Legion::API::Routes::AuthSaml.map_roles(['admin-group'])
        expect(roles).to eq(['admin'])
      end
    end
  end

  describe 'Routes::AuthSaml.saml_enabled?' do
    it 'returns true when OneLogin::RubySaml is defined and settings enabled' do
      expect(Legion::API::Routes::AuthSaml.saml_enabled?).to be true
    end
  end

  describe 'Routes::AuthSaml.resolve_saml_config' do
    it 'returns a Hash' do
      expect(Legion::API::Routes::AuthSaml.resolve_saml_config).to be_a(Hash)
    end

    it 'returns the configured idp_sso_url' do
      cfg = Legion::API::Routes::AuthSaml.resolve_saml_config
      expect(cfg[:idp_sso_url]).to eq('https://idp.example.com/saml/sso')
    end
  end
end
