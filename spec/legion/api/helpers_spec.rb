# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/identity/request'

RSpec.describe Legion::API::Helpers do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, true
      set :host_authorization, permitted: :any

      get '/test/meta' do
        content_type :json
        Legion::JSON.dump(response_meta)
      end

      get '/test/authenticated' do
        content_type :json
        Legion::JSON.dump({ authenticated: authenticated? })
      end
    end
  end

  def app
    test_app
  end

  describe '#response_meta' do
    context 'without authentication' do
      it 'returns timestamp and node' do
        get '/test/meta'
        body = Legion::JSON.load(last_response.body)
        expect(body[:timestamp]).not_to be_nil
        expect(body[:node]).to eq('test-node')
      end

      it 'does not include caller key' do
        get '/test/meta'
        body = Legion::JSON.load(last_response.body)
        expect(body).not_to have_key(:caller)
      end
    end

    context 'with authenticated request and a principal' do
      let(:principal) do
        Legion::Identity::Request.new(
          principal_id:   'user-123',
          canonical_name: 'jane-doe',
          kind:           :human,
          source:         :kerberos
        )
      end

      before do
        # Simulate Middleware::Auth setting legion.auth and Identity::Middleware setting legion.principal
        env_patch = { 'legion.auth' => { sub: 'user-123' }, 'legion.principal' => principal }
        rack_mock_session.cookie_jar['rack.session'] = nil
        allow_any_instance_of(Sinatra::Base).to receive(:env).and_return(
          Rack::MockRequest.env_for('/test/meta').merge(env_patch)
        )
      end

      it 'includes caller in meta' do
        get '/test/meta', {}, { 'legion.auth' => { sub: 'user-123' }, 'legion.principal' => principal }
        body = Legion::JSON.load(last_response.body)
        expect(body[:caller]).not_to be_nil
      end

      it 'sets canonical_name from principal' do
        get '/test/meta', {}, { 'legion.auth' => { sub: 'user-123' }, 'legion.principal' => principal }
        body = Legion::JSON.load(last_response.body)
        expect(body[:caller][:canonical_name]).to eq('jane-doe')
      end

      it 'sets kind from principal' do
        get '/test/meta', {}, { 'legion.auth' => { sub: 'user-123' }, 'legion.principal' => principal }
        body = Legion::JSON.load(last_response.body)
        expect(body[:caller][:kind]).to eq('human')
      end

      it 'sets source from principal' do
        get '/test/meta', {}, { 'legion.auth' => { sub: 'user-123' }, 'legion.principal' => principal }
        body = Legion::JSON.load(last_response.body)
        expect(body[:caller][:source]).to eq('kerberos')
      end
    end

    context 'with auth claims but no principal' do
      it 'does not include caller key when principal is nil' do
        get '/test/meta', {}, { 'legion.auth' => { sub: 'user-123' } }
        body = Legion::JSON.load(last_response.body)
        expect(body).not_to have_key(:caller)
      end
    end

    it 'timestamp is ISO 8601 format' do
      get '/test/meta'
      body = Legion::JSON.load(last_response.body)
      expect { Time.iso8601(body[:timestamp]) }.not_to raise_error
    end
  end

  describe '#authenticated?' do
    it 'returns false when no legion.auth in env' do
      get '/test/authenticated'
      body = Legion::JSON.load(last_response.body)
      expect(body[:authenticated]).to be false
    end

    it 'returns true when legion.auth is set' do
      get '/test/authenticated', {}, { 'legion.auth' => { sub: 'user-123' } }
      body = Legion::JSON.load(last_response.body)
      expect(body[:authenticated]).to be true
    end
  end
end
