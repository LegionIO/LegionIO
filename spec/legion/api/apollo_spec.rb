# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/apollo'

RSpec.describe 'Apollo API routes' do
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

      error do
        content_type :json
        err = env['sinatra.error']
        status 500
        Legion::JSON.dump({ error: { code: 'internal_error', message: err.message } })
      end

      register Legion::API::Routes::Apollo
    end
  end

  def app
    test_app
  end

  describe 'GET /api/apollo/status' do
    context 'when apollo is not loaded' do
      it 'returns 503 with available: false' do
        get '/api/apollo/status'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:available]).to be false
      end
    end

    context 'when apollo is loaded' do
      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)
      end

      it 'returns 200 with available: true' do
        get '/api/apollo/status'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:available]).to be true
        expect(body[:data][:data_connected]).to be true
      end
    end
  end

  describe 'GET /api/apollo/stats' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        get '/api/apollo/stats'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)
      end

      it 'returns stats with error when table is missing' do
        allow_any_instance_of(test_app).to receive(:apollo_stats)
          .and_return({ total_entries: 0, error: 'apollo_entries table not available' })

        get '/api/apollo/stats'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:total_entries]).to eq(0)
      end
    end
  end

  describe 'POST /api/apollo/query' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        post '/api/apollo/query', Legion::JSON.dump({ query: 'test' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      let(:fake_runner) { double('ApolloRunner') }

      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)

        runner = fake_runner
        allow_any_instance_of(test_app).to receive(:apollo_runner).and_return(runner)
      end

      it 'returns query results' do
        allow(fake_runner).to receive(:handle_query).and_return({ entries: [], total: 0 })

        post '/api/apollo/query', Legion::JSON.dump({ query: 'what is legion?' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:entries]).to eq([])
      end

      it 'passes parameters to handle_query' do
        expect(fake_runner).to receive(:handle_query).with(
          query:          'test query',
          limit:          5,
          min_confidence: 0.5,
          status:         [:confirmed],
          tags:           ['important'],
          domain:         'ops',
          agent_id:       'test-agent'
        ).and_return({ entries: [] })

        post '/api/apollo/query',
             Legion::JSON.dump({
                                 query:          'test query',
                                 limit:          5,
                                 min_confidence: 0.5,
                                 tags:           ['important'],
                                 domain:         'ops',
                                 agent_id:       'test-agent'
                               }),
             'CONTENT_TYPE' => 'application/json'
      end
    end
  end

  describe 'POST /api/apollo/ingest' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        post '/api/apollo/ingest', Legion::JSON.dump({ content: 'test' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      let(:fake_runner) { double('ApolloRunner') }

      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)

        runner = fake_runner
        allow_any_instance_of(test_app).to receive(:apollo_runner).and_return(runner)
      end

      it 'returns 201 on successful ingest' do
        allow(fake_runner).to receive(:handle_ingest).and_return({ success: true, id: 42 })

        post '/api/apollo/ingest',
             Legion::JSON.dump({ content: 'legion uses AMQP for messaging' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(201)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:success]).to be true
      end

      it 'passes parameters to handle_ingest' do
        expect(fake_runner).to receive(:handle_ingest).with(
          content:          'test content',
          content_type:     'fact',
          tags:             ['test'],
          source_agent:     'my-agent',
          source_provider:  'internal',
          source_channel:   'rest_api',
          knowledge_domain: 'ops',
          context:          { origin: 'spec' }
        ).and_return({ success: true })

        post '/api/apollo/ingest',
             Legion::JSON.dump({
                                 content:          'test content',
                                 content_type:     'fact',
                                 tags:             ['test'],
                                 source_agent:     'my-agent',
                                 source_provider:  'internal',
                                 knowledge_domain: 'ops',
                                 context:          { origin: 'spec' }
                               }),
             'CONTENT_TYPE' => 'application/json'
      end
    end
  end

  describe 'GET /api/apollo/entries/:id/related' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        get '/api/apollo/entries/1/related'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      let(:fake_runner) { double('ApolloRunner') }

      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)

        runner = fake_runner
        allow_any_instance_of(test_app).to receive(:apollo_runner).and_return(runner)
      end

      it 'returns related entries' do
        allow(fake_runner).to receive(:related_entries).and_return({ entries: [], total: 0 })

        get '/api/apollo/entries/42/related'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:entries]).to eq([])
      end

      it 'passes parsed parameters' do
        expect(fake_runner).to receive(:related_entries).with(
          entry_id:       42,
          relation_types: %w[supports contradicts],
          depth:          3
        ).and_return({ entries: [] })

        get '/api/apollo/entries/42/related?relation_types=supports,contradicts&depth=3'
      end
    end
  end

  describe 'GET /api/apollo/graph' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        get '/api/apollo/graph'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)
      end

      it 'returns graph topology' do
        allow_any_instance_of(test_app).to receive(:apollo_graph_topology)
          .and_return({ domains: { 'general' => 10 }, agents: { 'claude' => 8 },
                        relation_types: { 'similar_to' => 5 }, total_relations: 5,
                        confirmed: 8, candidates: 2, disputed_entries: 0 })

        get '/api/apollo/graph'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:domains]).to eq({ general: 10 })
        expect(body[:data][:total_relations]).to eq(5)
      end
    end
  end

  describe 'GET /api/apollo/expertise' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        get '/api/apollo/expertise'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)
      end

      it 'returns expertise map' do
        allow_any_instance_of(test_app).to receive(:apollo_expertise_map)
          .and_return({ domains: { 'general' => [{ agent_id: 'claude', proficiency: 0.8, entry_count: 10 }] },
                        total_agents: 1, total_domains: 1 })

        get '/api/apollo/expertise'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:total_agents]).to eq(1)
        expect(body[:data][:domains][:general].first[:agent_id]).to eq('claude')
      end
    end
  end

  describe 'POST /api/apollo/maintenance' do
    context 'when apollo is not loaded' do
      it 'returns 503' do
        post '/api/apollo/maintenance', Legion::JSON.dump({ action: 'decay_cycle' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when apollo is loaded' do
      before do
        knowledge_mod = Module.new
        stub_const('Legion::Extensions::Apollo::Runners::Knowledge', knowledge_mod)
        stub_const('Legion::Extensions::Apollo::Runners::Maintenance', Module.new)

        data_mod = Module.new do
          def self.respond_to?(method, *) = method == :connection || super
          def self.connection = Object.new
        end
        stub_const('Legion::Data', data_mod)
      end

      it 'rejects invalid actions' do
        post '/api/apollo/maintenance', Legion::JSON.dump({ action: 'drop_table' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(400)
      end

      it 'runs decay_cycle' do
        allow_any_instance_of(test_app).to receive(:run_maintenance)
          .with(:decay_cycle).and_return({ decayed: 5, archived: 1 })

        post '/api/apollo/maintenance', Legion::JSON.dump({ action: 'decay_cycle' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:decayed]).to eq(5)
      end

      it 'runs corroboration' do
        allow_any_instance_of(test_app).to receive(:run_maintenance)
          .with(:corroboration).and_return({ success: true, promoted: 3 })

        post '/api/apollo/maintenance', Legion::JSON.dump({ action: 'corroboration' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:promoted]).to eq(3)
      end
    end
  end
end
