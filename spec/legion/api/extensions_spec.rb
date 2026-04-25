# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/extensions'

RSpec.describe Legion::API::Routes::Extensions do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
    loader.settings[:data] = {}
    loader.settings[:transport] = {}
    loader.settings[:extensions] = {}
  end

  let(:fake_runner) do
    Module.new do
      def self.name
        'Legion::Extensions::FakeExt::Runners::Things'
      end

      def self.to_s
        name
      end

      define_method(:do_stuff) { |_opts = {}| nil }
      define_method(:do_other) { |_opts = {}| nil }
    end
  end

  let(:fake_extension) do
    runner = fake_runner
    Module.new do
      define_singleton_method(:name) { 'Legion::Extensions::FakeExt' }
      define_singleton_method(:to_s) { name }

      const_set(:VERSION, '1.2.3')

      define_singleton_method(:runner_modules) { [runner] }

      define_singleton_method(:runners) do
        {
          things: {
            runner_module: runner,
            runner_class:  runner.name,
            runner_name:   'things',
            class_methods: {
              do_stuff: { args: [%i[opt opts]] },
              do_other: { args: [%i[opt opts]] }
            }
          }
        }
      end
    end
  end

  before do
    Legion::Extensions::Catalog.reset!
    Legion::Extensions.reset_runtime_handles!
    Legion::Extensions::Catalog.register('lex-fake_ext', state: :running)
    Legion::Extensions::Catalog.transition('lex-fake_ext', :running)
    Legion::Extensions.register_extension_handle('lex-fake_ext',
                                                 state:                    :running,
                                                 active_version:           '1.2.3',
                                                 latest_installed_version: '1.2.4',
                                                 reload_state:             :pending,
                                                 hot_reloadable:           true,
                                                 runners:                  ['things'])

    allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([fake_extension])
  end

  after do
    Legion::Extensions.reset_runtime_handles!
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers

      set :show_exceptions, false
      set :raise_errors, true
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Extensions
    end
  end

  def app
    test_app
  end

  describe 'GET /api/extension_catalog' do
    it 'returns runtime handles as the authoritative loaded extensions' do
      get '/api/extension_catalog'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      entry = body[:data].find { |e| e[:name] == 'lex-fake_ext' }
      expect(entry).to include(
        state:                    'running',
        active_version:           '1.2.3',
        latest_installed_version: '1.2.4',
        reload_state:             'pending',
        pending_reload:           true,
        hot_reloadable:           true
      )
    end

    it 'filters by state when ?state= param given' do
      Legion::Extensions::Catalog.register('lex-stopped', state: :stopped)
      get '/api/extension_catalog?state=running'
      body = Legion::JSON.load(last_response.body)
      names = body[:data].map { |e| e[:name] }
      expect(names).to include('lex-fake_ext')
      expect(names).not_to include('lex-stopped')
    end
  end

  describe 'GET /api/extension_catalog/available' do
    it 'returns the full ecosystem list' do
      get '/api/extension_catalog/available'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].length).to be > 100
      expect(body[:data].first).to have_key(:name)
      expect(body[:data].first).to have_key(:category)
    end

    it 'filters by ?category= param' do
      get '/api/extension_catalog/available?category=ai'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to all(include(category: 'ai'))
    end
  end

  describe 'GET /api/extension_catalog/:name' do
    it 'returns extension detail' do
      get '/api/extension_catalog/lex-fake_ext'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('lex-fake_ext')
      expect(body[:data][:state]).to eq('running')
      expect(body[:data][:active_version]).to eq('1.2.3')
      expect(body[:data][:pending_reload]).to be true
      expect(body[:data][:runners]).to be_an(Array)
    end

    it 'returns 404 for unknown extension' do
      get '/api/extension_catalog/lex-nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /api/extension_catalog/:name/runners' do
    it 'returns runners for the extension' do
      get '/api/extension_catalog/lex-fake_ext/runners'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].first[:name]).to eq('things')
    end
  end

  describe 'GET /api/extension_catalog/:name/runners/:runner_name' do
    it 'returns runner detail with functions' do
      get '/api/extension_catalog/lex-fake_ext/runners/things'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('things')
      expect(body[:data][:functions]).to include('do_stuff', 'do_other')
    end

    it 'returns 404 for unknown runner' do
      get '/api/extension_catalog/lex-fake_ext/runners/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /api/extension_catalog/:name/runners/:runner_name/functions' do
    it 'returns function list' do
      get '/api/extension_catalog/lex-fake_ext/runners/things/functions'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].map { |f| f[:name] }).to include('do_stuff', 'do_other')
    end
  end

  describe 'GET /api/extension_catalog/:name/runners/:runner_name/functions/:function_name' do
    it 'returns function detail' do
      get '/api/extension_catalog/lex-fake_ext/runners/things/functions/do_stuff'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('do_stuff')
    end

    it 'returns 404 for unknown function' do
      get '/api/extension_catalog/lex-fake_ext/runners/things/functions/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end
end
