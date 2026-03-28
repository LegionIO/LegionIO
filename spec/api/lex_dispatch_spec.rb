# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'LexDispatch v3.0 Routes' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:mock_router) { Legion::API.router }

  before { mock_router.clear! }

  describe 'GET /api/extensions/index' do
    it 'returns empty array when no extensions registered' do
      get '/api/extensions/index'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:extensions]).to eq([])
    end

    it 'lists registered extension names' do
      mock_router.register_extension_route(
        lex_name: 'my_ext', amqp_prefix: 'lex.my.ext',
        component_type: 'runners', component_name: 'fetcher',
        method_name: 'fetch', runner_class: 'Lex::MyExt::Runners::Fetcher',
        definition: nil
      )
      get '/api/extensions/index'
      body = Legion::JSON.load(last_response.body)
      expect(body[:extensions]).to include('my_ext')
    end
  end

  describe 'GET /api/extensions/:lex/:type/:name/:method' do
    it 'returns route contract with definition' do
      mock_router.register_extension_route(
        lex_name: 'my_ext', amqp_prefix: 'lex.my.ext',
        component_type: 'runners', component_name: 'fetcher',
        method_name: 'fetch', runner_class: 'Lex::MyExt::Runners::Fetcher',
        definition: { desc: 'fetch data', inputs: { url: { type: :string } } }
      )

      get '/api/extensions/my_ext/runners/fetcher/fetch'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:extension]).to eq('my_ext')
      expect(body[:component_type]).to eq('runners')
      expect(body[:method]).to eq('fetch')
      expect(body[:definition][:desc]).to eq('fetch data')
    end

    it 'returns 404 for unknown route' do
      get '/api/extensions/unknown/runners/nothing/nope'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /api/extensions/:lex/:type/:name/:method' do
    before do
      mock_router.register_extension_route(
        lex_name: 'my_ext', amqp_prefix: 'lex.my.ext',
        component_type: 'runners', component_name: 'fetcher',
        method_name: 'fetch', runner_class: 'Lex::MyExt::Runners::Fetcher',
        definition: nil
      )

      # Ensure the constant exists so extension_loaded_locally? returns true
      stub_const('Lex::MyExt::Runners::Fetcher', Class.new)
    end

    it 'dispatches to Ingress.run with correct params' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 42, status: 'queued', result: nil })

      post '/api/extensions/my_ext/runners/fetcher/fetch',
           Legion::JSON.dump({ url: 'https://example.com' }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(
          runner_class: 'Lex::MyExt::Runners::Fetcher',
          function:     :fetch,
          source:       'lex_dispatch'
        )
      )
    end

    it 'returns 404 for unregistered route' do
      post '/api/extensions/my_ext/runners/fetcher/nonexistent',
           Legion::JSON.dump({}),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(404)
    end

    it 'returns 400 for invalid JSON body' do
      post '/api/extensions/my_ext/runners/fetcher/fetch',
           'not-json{{{',
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(400)
    end

    it 'includes envelope fields from X-Legion headers' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 1, status: 'queued', result: nil })

      post '/api/extensions/my_ext/runners/fetcher/fetch',
           Legion::JSON.dump({}),
           'CONTENT_TYPE'                  => 'application/json',
           'HTTP_X_LEGION_CONVERSATION_ID' => 'conv-123'

      body = Legion::JSON.load(last_response.body)
      expect(body[:conversation_id]).to eq('conv-123')
    end

    it 'handles empty body gracefully' do
      allow(Legion::Ingress).to receive(:run).and_return({ task_id: 5, status: 'queued', result: nil })

      post '/api/extensions/my_ext/runners/fetcher/fetch'

      expect(last_response.status).to eq(200)
    end
  end

  describe 'GET /api/discovery' do
    it 'includes extensions in discovery response' do
      mock_router.register_extension_route(
        lex_name: 'github', amqp_prefix: 'lex.github',
        component_type: 'runners', component_name: 'repo',
        method_name: 'list', runner_class: 'Lex::Github::Runners::Repo',
        definition: nil
      )

      get '/api/discovery'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:extensions]).to include('github')
    end
  end
end
