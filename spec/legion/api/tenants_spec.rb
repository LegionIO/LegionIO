# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/tenants'

RSpec.describe 'Tenants API routes' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
    loader.settings[:data] = { connected: false }
    loader.settings[:transport] = { connected: false }
    loader.settings[:extensions] = {}
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Tenants
    end
  end

  def app
    test_app
  end

  describe 'POST /api/tenants' do
    it 'returns 201 when a tenant is created' do
      tenants_mod = Module.new do
        def self.create(**attrs)
          attrs
        end
      end
      stub_const('Legion::Tenants', tenants_mod)

      post '/api/tenants',
           Legion::JSON.dump({ tenant_id: 'askid-001', name: 'Core Platform', max_workers: 12 }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(201)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:tenant_id]).to eq('askid-001')
      expect(body[:data][:max_workers]).to eq(12)
    end

    it 'returns 409 when the tenant create call reports a conflict' do
      tenants_mod = Module.new do
        def self.create(**)
          { error: 'tenant_exists' }
        end
      end
      stub_const('Legion::Tenants', tenants_mod)

      post '/api/tenants',
           Legion::JSON.dump({ tenant_id: 'askid-001', name: 'Core Platform' }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(409)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error]).to eq('tenant_exists')
    end
  end
end
