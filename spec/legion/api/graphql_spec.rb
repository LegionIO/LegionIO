# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'

# Load GraphQL gem or skip entire suite
begin
  require 'graphql'
  GRAPHQL_AVAILABLE = true
rescue LoadError
  GRAPHQL_AVAILABLE = false
end

require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/graphql' if GRAPHQL_AVAILABLE

RSpec.describe 'GraphQL API routes', skip: !GRAPHQL_AVAILABLE && 'graphql gem not available' do
  include Rack::Test::Methods

  before(:all) do
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('../../..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client]    = { name: 'test-node', ready: true }
    loader.settings[:data]      = { connected: false }
    loader.settings[:transport] = { connected: false }
    loader.settings[:extensions] = {}
  end

  let(:test_app) do
    Class.new(Sinatra::Base) do
      helpers Legion::API::Helpers
      helpers Legion::API::Validators

      set :show_exceptions, false
      set :raise_errors,    false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::GraphQL
    end
  end

  def app
    test_app
  end

  def graphql_post(query, variables: {}, operation_name: nil)
    payload = { query: query }
    payload[:variables]      = variables      unless variables.empty?
    payload[:operationName]  = operation_name if operation_name
    post '/api/graphql', Legion::JSON.dump(payload), 'CONTENT_TYPE' => 'application/json'
  end

  def response_body
    Legion::JSON.load(last_response.body)
  end

  # ── GET /api/graphql (GraphiQL UI) ───────────────────────────────────────────

  describe 'GET /api/graphql' do
    it 'returns 200' do
      get '/api/graphql'
      expect(last_response.status).to eq(200)
    end

    it 'returns HTML content type' do
      get '/api/graphql'
      expect(last_response.content_type).to include('text/html')
    end

    it 'includes GraphiQL script tag' do
      get '/api/graphql'
      expect(last_response.body).to include('graphiql')
    end

    it 'includes the /api/graphql endpoint URL' do
      get '/api/graphql'
      expect(last_response.body).to include('/api/graphql')
    end
  end

  # ── POST /api/graphql — request validation ───────────────────────────────────

  describe 'POST /api/graphql — request validation' do
    it 'returns 400 when query is missing' do
      post '/api/graphql', Legion::JSON.dump({}), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:errors].first[:message]).to eq('query is required')
    end

    it 'returns 400 when body is empty' do
      post '/api/graphql', '', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 when query is blank string' do
      post '/api/graphql', Legion::JSON.dump({ query: '   ' }), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end
  end

  # ── introspection ────────────────────────────────────────────────────────────

  describe 'POST /api/graphql — introspection' do
    it 'responds to __typename query' do
      graphql_post('{ __typename }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:__typename]).to eq('Query')
    end

    it 'supports __schema introspection' do
      graphql_post('{ __schema { queryType { name } } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:__schema][:queryType][:name]).to eq('Query')
    end

    it 'returns type information for Worker' do
      graphql_post('{ __type(name: "Worker") { name fields { name } } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:__type][:name]).to eq('Worker')
    end

    it 'returns type information for Extension' do
      graphql_post('{ __type(name: "Extension") { name fields { name } } }')
      body = response_body
      expect(body[:data][:__type][:name]).to eq('Extension')
    end

    it 'returns type information for Task' do
      graphql_post('{ __type(name: "Task") { name fields { name } } }')
      body = response_body
      expect(body[:data][:__type][:name]).to eq('Task')
    end

    it 'returns type information for Node' do
      graphql_post('{ __type(name: "Node") { name fields { name } } }')
      body = response_body
      expect(body[:data][:__type][:name]).to eq('Node')
    end
  end

  # ── node query ───────────────────────────────────────────────────────────────

  describe 'node query' do
    it 'returns node data' do
      graphql_post('{ node { name version ready } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data]).to have_key(:node)
    end

    it 'returns node name' do
      graphql_post('{ node { name } }')
      body = response_body
      expect(body[:data][:node][:name]).to eq('test-node')
    end

    it 'returns node version' do
      graphql_post('{ node { version } }')
      body = response_body
      expect(body[:data][:node][:version]).to eq(Legion::VERSION)
    end

    it 'returns ready field as boolean' do
      graphql_post('{ node { ready } }')
      body = response_body
      expect([true, false]).to include(body[:data][:node][:ready])
    end

    it 'returns uptime field (nil when process not started)' do
      graphql_post('{ node { uptime } }')
      body = response_body
      expect(body[:data][:node]).to have_key(:uptime)
    end
  end

  # ── workers query ─────────────────────────────────────────────────────────────

  describe 'workers query' do
    it 'returns empty array when no data layer' do
      graphql_post('{ workers { id name } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:workers]).to be_an(Array)
    end

    it 'accepts status filter argument' do
      graphql_post('{ workers(status: "active") { id name status } }')
      expect(last_response.status).to eq(200)
    end

    it 'accepts risk_tier filter argument' do
      graphql_post('{ workers(riskTier: "tier1") { id name riskTier } }')
      expect(last_response.status).to eq(200)
    end

    it 'accepts limit argument' do
      graphql_post('{ workers(limit: 5) { id name } }')
      expect(last_response.status).to eq(200)
    end

    it 'returns worker type fields' do
      graphql_post('{ workers { id name status riskTier team extension createdAt } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).not_to have_key(:errors)
    end
  end

  # ── worker query (single) ─────────────────────────────────────────────────────

  describe 'worker query' do
    it 'returns nil when worker not found' do
      graphql_post('{ worker(id: "99999") { id name } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:worker]).to be_nil
    end

    it 'requires id argument' do
      graphql_post('{ worker { id name } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).to have_key(:errors)
    end
  end

  # ── extensions query ──────────────────────────────────────────────────────────

  describe 'extensions query' do
    it 'returns array' do
      graphql_post('{ extensions { name version status } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:extensions]).to be_an(Array)
    end

    it 'accepts status filter argument' do
      graphql_post('{ extensions(status: "active") { name } }')
      expect(last_response.status).to eq(200)
    end

    it 'returns extension type fields' do
      graphql_post('{ extensions { name version status description riskTier runners } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).not_to have_key(:errors)
    end
  end

  # ── extension query (single) ───────────────────────────────────────────────────

  describe 'extension query' do
    it 'returns nil when not found' do
      graphql_post('{ extension(name: "lex-nonexistent") { name version } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:extension]).to be_nil
    end

    it 'requires name argument' do
      graphql_post('{ extension { name } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).to have_key(:errors)
    end
  end

  # ── tasks query ───────────────────────────────────────────────────────────────

  describe 'tasks query' do
    it 'returns empty array when no data layer' do
      graphql_post('{ tasks { id status } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:tasks]).to be_an(Array)
    end

    it 'accepts status filter argument' do
      graphql_post('{ tasks(status: "completed") { id status } }')
      expect(last_response.status).to eq(200)
    end

    it 'accepts limit argument' do
      graphql_post('{ tasks(limit: 10) { id } }')
      expect(last_response.status).to eq(200)
    end

    it 'returns task type fields' do
      graphql_post('{ tasks { id status extension runner function createdAt completedAt } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).not_to have_key(:errors)
    end
  end

  # ── field selection / partial queries ─────────────────────────────────────────

  describe 'field selection' do
    it 'allows selecting only specific worker fields' do
      graphql_post('{ workers { name } }')
      expect(last_response.status).to eq(200)
    end

    it 'allows selecting only name from extensions' do
      graphql_post('{ extensions { name } }')
      expect(last_response.status).to eq(200)
    end

    it 'allows selecting only node name' do
      graphql_post('{ node { name } }')
      body = response_body
      expect(body[:data][:node]).to eq({ name: 'test-node' })
    end
  end

  # ── variables support ─────────────────────────────────────────────────────────

  describe 'variables' do
    it 'passes variables to the query' do
      query = 'query GetWorker($id: ID!) { worker(id: $id) { id name } }'
      graphql_post(query, variables: { id: '99999' })
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body[:data][:worker]).to be_nil
    end

    it 'passes filter variables to workers query' do
      query = 'query Workers($status: String) { workers(status: $status) { id } }'
      graphql_post(query, variables: { status: 'active' })
      expect(last_response.status).to eq(200)
    end
  end

  # ── error handling ────────────────────────────────────────────────────────────

  describe 'error handling' do
    it 'returns errors for invalid field names' do
      graphql_post('{ workers { nonExistentField } }')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).to have_key(:errors)
    end

    it 'returns errors for invalid syntax' do
      graphql_post('{ this is not valid graphql !!!}')
      expect(last_response.status).to eq(200)
      body = response_body
      expect(body).to have_key(:errors)
    end

    it 'returns 200 even when query has errors (GraphQL convention)' do
      graphql_post('{ workers { badfield } }')
      expect(last_response.status).to eq(200)
    end
  end

  # ── schema constraints ────────────────────────────────────────────────────────

  describe 'schema constraints' do
    it 'enforces max_depth via schema configuration' do
      expect(Legion::API::GraphQL::Schema.max_depth).to eq(10)
    end

    it 'enforces max_complexity via schema configuration' do
      expect(Legion::API::GraphQL::Schema.max_complexity).to eq(200)
    end

    it 'has query type set' do
      expect(Legion::API::GraphQL::Schema.query).to eq(Legion::API::GraphQL::Types::QueryType)
    end
  end
end
