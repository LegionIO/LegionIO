# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'

RSpec.describe Legion::API::Routes::Extensions do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
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
    Legion::Extensions::Catalog.register('lex-fake_ext', state: :running)
    Legion::Extensions::Catalog.transition('lex-fake_ext', :running)

    allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([fake_extension])
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

  describe 'GET /api/extensions' do
    it 'returns loaded extensions from catalog' do
      get '/api/extensions'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      names = body[:data].map { |e| e[:name] }
      expect(names).to include('lex-fake_ext')
    end

    it 'filters by state when ?state= param given' do
      Legion::Extensions::Catalog.register('lex-stopped', state: :stopped)
      get '/api/extensions?state=running'
      body = Legion::JSON.load(last_response.body)
      names = body[:data].map { |e| e[:name] }
      expect(names).to include('lex-fake_ext')
      expect(names).not_to include('lex-stopped')
    end
  end

  describe 'GET /api/extensions/available' do
    it 'returns the full ecosystem list' do
      get '/api/extensions/available'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].length).to be > 100
      expect(body[:data].first).to have_key(:name)
      expect(body[:data].first).to have_key(:category)
    end

    it 'filters by ?category= param' do
      get '/api/extensions/available?category=ai'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to all(include(category: 'ai'))
    end
  end

  describe 'GET /api/extensions/:name' do
    it 'returns extension detail' do
      get '/api/extensions/lex-fake_ext'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('lex-fake_ext')
      expect(body[:data][:state]).to eq('running')
      expect(body[:data][:runners]).to be_an(Array)
    end

    it 'returns 404 for unknown extension' do
      get '/api/extensions/lex-nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /api/extensions/:name/runners' do
    it 'returns runners for the extension' do
      get '/api/extensions/lex-fake_ext/runners'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].first[:name]).to eq('things')
    end
  end

  describe 'GET /api/extensions/:name/runners/:runner_name' do
    it 'returns runner detail with functions' do
      get '/api/extensions/lex-fake_ext/runners/things'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('things')
      expect(body[:data][:functions]).to include('do_stuff', 'do_other')
    end

    it 'returns 404 for unknown runner' do
      get '/api/extensions/lex-fake_ext/runners/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /api/extensions/:name/runners/:runner_name/functions' do
    it 'returns function list' do
      get '/api/extensions/lex-fake_ext/runners/things/functions'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].map { |f| f[:name] }).to include('do_stuff', 'do_other')
    end
  end

  describe 'GET /api/extensions/:name/runners/:runner_name/functions/:function_name' do
    it 'returns function detail' do
      get '/api/extensions/lex-fake_ext/runners/things/functions/do_stuff'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('do_stuff')
    end

    it 'returns 404 for unknown function' do
      get '/api/extensions/lex-fake_ext/runners/things/functions/nonexistent'
      expect(last_response.status).to eq(404)
    end
  end
end
