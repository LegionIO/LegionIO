# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Lex Routes API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    Legion::API.route_registry.clear
  end

  # ---------------------------------------------------------------------------
  # Registry class methods
  # ---------------------------------------------------------------------------

  describe 'route_registry' do
    it 'starts empty' do
      expect(Legion::API.route_registry).to eq({})
    end
  end

  describe '.register_route' do
    it 'stores a route in the registry' do
      Legion::API.register_route(
        lex_name:     'my_ext',
        runner_name:  'my_runner',
        function:     'process',
        runner_class: 'Lex::MyExt::Runners::MyRunner',
        route_path:   'my_ext/my_runner/process'
      )
      expect(Legion::API.route_registry).to have_key('my_ext/my_runner/process')
    end
  end

  describe '.find_route_by_path' do
    it 'finds a route by exact path' do
      Legion::API.register_route(
        lex_name:     'some_ext',
        runner_name:  'some_runner',
        function:     'run',
        runner_class: 'Lex::SomeExt::Runners::SomeRunner',
        route_path:   'some_ext/some_runner/run'
      )
      result = Legion::API.find_route_by_path('some_ext/some_runner/run')
      expect(result).not_to be_nil
      expect(result[:lex_name]).to eq('some_ext')
      expect(result[:runner_name]).to eq('some_runner')
      expect(result[:function]).to eq('run')
      expect(result[:runner_class]).to eq('Lex::SomeExt::Runners::SomeRunner')
      expect(result[:route_path]).to eq('some_ext/some_runner/run')
    end

    it 'returns nil for unknown paths' do
      expect(Legion::API.find_route_by_path('nonexistent/path')).to be_nil
    end
  end

  describe '.registered_routes' do
    it 'lists all registered routes' do
      Legion::API.register_route(
        lex_name: 'ext_a', runner_name: 'runner_a', function: 'do_it',
        runner_class: 'Lex::ExtA::Runners::RunnerA', route_path: 'ext_a/runner_a/do_it'
      )
      Legion::API.register_route(
        lex_name: 'ext_b', runner_name: 'runner_b', function: 'run',
        runner_class: 'Lex::ExtB::Runners::RunnerB', route_path: 'ext_b/runner_b/run'
      )
      routes = Legion::API.registered_routes
      expect(routes.length).to eq(2)
      expect(routes.map { |r| r[:lex_name] }).to contain_exactly('ext_a', 'ext_b')
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/lex
  # ---------------------------------------------------------------------------

  describe 'GET /api/lex' do
    it 'returns an empty array when no routes are registered' do
      get '/api/lex'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to eq([])
    end

    it 'lists routes with expected keys' do
      Legion::API.register_route(
        lex_name:     'my_ext',
        runner_name:  'my_runner',
        function:     'process',
        runner_class: 'Lex::MyExt::Runners::MyRunner',
        route_path:   'my_ext/my_runner/process'
      )
      get '/api/lex'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].length).to eq(1)

      route = body[:data].first
      expect(route[:endpoint]).to eq('/api/lex/my_ext/my_runner/process')
      expect(route[:extension]).to eq('my_ext')
      expect(route[:runner]).to eq('my_runner')
      expect(route[:function]).to eq('process')
      expect(route[:runner_class]).to eq('Lex::MyExt::Runners::MyRunner')
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/lex/*
  # ---------------------------------------------------------------------------

  describe 'POST /api/lex/*' do
    let(:runner_class) { 'Lex::MyExt::Runners::MyRunner' }

    before do
      Legion::API.register_route(
        lex_name:     'my_ext',
        runner_name:  'my_runner',
        function:     'process',
        runner_class: runner_class,
        route_path:   'my_ext/my_runner/process'
      )
    end

    it 'returns 404 for an unregistered route' do
      post '/api/lex/nonexistent/route'
      expect(last_response.status).to eq(404)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('route_not_found')
    end

    it 'dispatches to Ingress.run with correct args' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 42, status: 'queued' })

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({ key: 'value' }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(
          runner_class:  runner_class,
          function:      'process',
          source:        'lex_route',
          generate_task: true
        )
      )
    end

    it 'passes parsed JSON body as payload' do
      received_payload = nil
      allow(Legion::Ingress).to receive(:run) do |args|
        received_payload = args[:payload]
        { task_id: 1, status: 'queued' }
      end

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({ name: 'test', value: 123 }),
           'CONTENT_TYPE' => 'application/json'

      expect(received_payload[:name]).to eq('test')
      expect(received_payload[:value]).to eq(123)
    end

    it 'injects http_method into payload' do
      received_payload = nil
      allow(Legion::Ingress).to receive(:run) do |args|
        received_payload = args[:payload]
        { task_id: 2, status: 'queued' }
      end

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({ foo: 'bar' }),
           'CONTENT_TYPE' => 'application/json'

      expect(received_payload[:http_method]).to eq('POST')
    end

    it 'injects headers into payload' do
      received_payload = nil
      allow(Legion::Ingress).to receive(:run) do |args|
        received_payload = args[:payload]
        { task_id: 3, status: 'queued' }
      end

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({}),
           'CONTENT_TYPE' => 'application/json'

      expect(received_payload[:headers]).to be_a(Hash)
      expect(received_payload[:headers]).to have_key('CONTENT_TYPE')
    end

    it 'handles empty body gracefully' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 5, status: 'queued' })

      post '/api/lex/my_ext/my_runner/process'

      expect(last_response.status).to eq(200)
      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(runner_class: runner_class, function: 'process')
      )
    end

    it 'returns Ingress result fields' do
      allow(Legion::Ingress).to receive(:run).and_return(
        { task_id: 99, status: 'queued', result: nil }
      )

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({}),
           'CONTENT_TYPE' => 'application/json'

      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:task_id]).to eq(99)
      expect(body[:data][:status]).to eq('queued')
    end

    it 'returns error result from Ingress on failure' do
      allow(Legion::Ingress).to receive(:run).and_return(
        { task_id: nil, status: 'error', result: 'something went wrong' }
      )

      post '/api/lex/my_ext/my_runner/process',
           Legion::JSON.dump({}),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:status]).to eq('error')
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/lex/* (non-POST methods not supported for auto-routes)
  # ---------------------------------------------------------------------------

  describe 'GET /api/lex/:path (wildcard)' do
    it 'returns 404 for wildcard GET (only POST supported for auto-routes)' do
      Legion::API.register_route(
        lex_name:     'my_ext',
        runner_name:  'my_runner',
        function:     'process',
        runner_class: 'Lex::MyExt::Runners::MyRunner',
        route_path:   'my_ext/my_runner/process'
      )
      get '/api/lex/my_ext/my_runner/process'
      expect(last_response.status).to eq(404)
    end
  end
end
