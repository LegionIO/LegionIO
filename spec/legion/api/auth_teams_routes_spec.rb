# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/auth_teams'

RSpec.describe Legion::API::Routes::AuthTeams do
  include Rack::Test::Methods

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::AuthTeams
    end
  end

  def app
    test_app
  end

  let(:state) { 'state-123' }
  let(:entry) do
    { verifier: 'v', created_at: Time.now, result: nil, tenant_id: 'tid', client_id: 'cid',
      redirect_uri: 'http://127.0.0.1:4567/api/auth/teams/callback', scopes: 'User.Read offline_access' }
  end

  before do
    Legion::API::Routes::AuthTeams.mutex.synchronize { Legion::API::Routes::AuthTeams.pending.clear }
  end

  def add_pending
    described_class.mutex.synchronize { described_class.pending[state] = entry }
  end

  describe 'GET /api/auth/teams/callback' do
    it 'shows the LegionIO success page and stores the delegated token' do
      add_pending
      allow_any_instance_of(test_app).to receive(:exchange_teams_code)
        .and_return(access_token: 'at', refresh_token: 'rt', expires_in: 3600, scope: 'User.Read')
      allow_any_instance_of(test_app).to receive(:store_teams_token).and_return(true)

      get '/api/auth/teams/callback', code: 'c', state: state

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/html')
      expect(last_response.body).to include('LegionIO &mdash; Microsoft Teams / Entra sign-in complete', 'You can close this tab.')
      expect(entry[:result]).to eq(authenticated: true)
    end

    it 'shows the failure page with the error Microsoft returned and suggests legionio auth teams' do
      add_pending

      get '/api/auth/teams/callback', state: state, error: 'access_denied', error_description: 'AADSTS65004: User declined'

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('LegionIO &mdash; Microsoft Teams / Entra sign-in failed', 'You can close this tab.',
                                            'access_denied', 'AADSTS65004: User declined', 'legionio auth teams')
      expect(entry[:result]).to eq(authenticated: false, error: 'access_denied')
    end

    it 'shows the failure page for an unknown or expired state' do
      get '/api/auth/teams/callback', code: 'c', state: 'nope'

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('sign-in failed', 'unknown_state', 'legionio auth teams')
    end

    it 'shows the failure page with the token endpoint error' do
      add_pending
      allow_any_instance_of(test_app).to receive(:exchange_teams_code)
        .and_return(error: 'invalid_grant', error_description: 'AADSTS70008: code expired')

      get '/api/auth/teams/callback', code: 'c', state: state

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('sign-in failed', 'invalid_grant', 'AADSTS70008: code expired')
      expect(entry[:result]).to include(authenticated: false)
    end

    it 'does not report success when the token could not be stored' do
      add_pending
      allow_any_instance_of(test_app).to receive(:exchange_teams_code).and_return(access_token: 'at')
      allow_any_instance_of(test_app).to receive(:store_teams_token).and_return(false)

      get '/api/auth/teams/callback', code: 'c', state: state

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('sign-in failed', 'token_store_failed')
      expect(entry[:result]).to eq(authenticated: false, error: 'token_store_failed')
    end

    it 'escapes HTML in the error text' do
      add_pending
      get '/api/auth/teams/callback', state: state, error: '<script>x</script>'
      expect(last_response.body).not_to include('<script>x</script>')
      expect(last_response.body).to include('&lt;script&gt;')
    end
  end

  describe 'POST /api/auth/teams/authorize' do
    before do
      allow(Legion::Settings).to receive(:[]).and_call_original
      allow(Legion::Settings).to receive(:dig).and_call_original
    end

    it 'falls back to identity.entra.auth tenant/client when microsoft_teams has none' do
      allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return({})
      allow(Legion::Settings).to receive(:dig).with(:identity, :entra, :auth).and_return(tenant_id: 'etid', client_id: 'ecid')

      post '/api/auth/teams/authorize', '{}', 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      url = Legion::JSON.load(last_response.body)[:data][:authorize_url]
      expect(url).to include('login.microsoftonline.com/etid/', 'client_id=ecid')
    end

    it 'requests the Entra delegated scope set when no scopes are configured' do
      allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return(tenant_id: 't', client_id: 'c')
      stub_const('Legion::Extensions::Identity::Entra::Helpers::Scopes',
                 Module.new { def self.resolve(pattern:) = "openid offline_access User.Read #{pattern}" })

      post '/api/auth/teams/authorize', '{}', 'CONTENT_TYPE' => 'application/json'

      state = Legion::JSON.load(last_response.body)[:data][:state]
      expect(described_class.pending[state][:scopes]).to eq('openid offline_access User.Read delegated')
    end

    it 'returns 422 when no tenant/client is configured anywhere' do
      allow(Legion::Settings).to receive(:[]).with(:microsoft_teams).and_return({})
      allow(Legion::Settings).to receive(:dig).with(:identity, :entra, :auth).and_return(nil)

      post '/api/auth/teams/authorize', '{}', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
    end
  end

  describe Legion::API::Routes::AuthTeams::CallbackPage do
    it 'uses the lex-identity-entra page when it is loaded' do
      entra_page = Module.new do
        def self.success_html = 'entra-success'
        def self.failure_html(*) = 'entra-failure'
      end
      stub_const('Legion::Extensions::Identity::Entra::Helpers::CallbackPage', entra_page)

      expect(described_class.success_html).to eq('entra-success')
      expect(described_class.failure_html('x')).to eq('entra-failure')
    end

    it 'falls back to an identical built-in page without lex-identity-entra' do
      hide_const('Legion::Extensions::Identity::Entra::Helpers::CallbackPage')
      expect(described_class.success_html).to include('LegionIO &mdash; Microsoft Teams / Entra sign-in complete')
      expect(described_class.failure_html('boom')).to include('sign-in failed', 'boom', 'legionio auth teams')
    end
  end
end
