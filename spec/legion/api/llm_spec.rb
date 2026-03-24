# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/llm'

RSpec.describe 'LLM API routes' do
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

      register Legion::API::Routes::Llm
    end
  end

  def app
    test_app
  end

  # ──────────────────────────────────────────────────────────
  # Helper stubs
  # ──────────────────────────────────────────────────────────

  def stub_llm_started
    llm_mod = Module.new do
      def self.started? = true
    end
    stub_const('Legion::LLM', llm_mod)
  end

  def stub_cache_available
    cache_mod = Module.new do
      def self.connected? = true
    end
    stub_const('Legion::Cache', cache_mod) unless defined?(Legion::Cache)
    allow(Legion::Cache).to receive(:connected?).and_return(true)
  end

  def stub_cache_unavailable
    cache_mod = Module.new do
      def self.connected? = false
    end
    stub_const('Legion::Cache', cache_mod) unless defined?(Legion::Cache)
    allow(Legion::Cache).to receive(:connected?).and_return(false)
  end

  def stub_response_cache
    rc = Module.new do
      module_function

      def init_request(_id, ttl: 300); end
      def complete(_id, response:, meta:, ttl: 300); end
      def fail_request(_id, code:, message:, ttl: 300); end
    end
    stub_const('Legion::LLM::ResponseCache', rc)
  end

  def stub_llm_sync_response(content: 'hello from LLM', model_name: 'claude-sonnet-4-6')
    fake_response = double('LLMResponse',
                           content:       content,
                           input_tokens:  5,
                           output_tokens: 10)
    allow(fake_response).to receive(:respond_to?).with(:input_tokens).and_return(true)
    allow(fake_response).to receive(:respond_to?).with(:output_tokens).and_return(true)

    fake_session = double('ChatSession', model: model_name)
    allow(fake_session).to receive(:ask).and_return(fake_response)

    allow(Legion::LLM).to receive(:chat).and_return(fake_session)
  end

  # ──────────────────────────────────────────────────────────
  # 503 when LLM not started
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/llm/chat — LLM unavailable' do
    context 'when Legion::LLM is not defined' do
      it 'returns 503 with llm_unavailable code' do
        post '/api/llm/chat', Legion::JSON.dump({ message: 'hello' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('llm_unavailable')
      end
    end

    context 'when Legion::LLM is defined but not started' do
      before do
        llm_mod = Module.new { def self.started? = false }
        stub_const('Legion::LLM', llm_mod)
      end

      it 'returns 503 with llm_unavailable code' do
        post '/api/llm/chat', Legion::JSON.dump({ message: 'hello' }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('llm_unavailable')
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # 400 when message missing
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/llm/chat — missing message' do
    before { stub_llm_started }

    it 'returns 400 when message field is absent' do
      post '/api/llm/chat', Legion::JSON.dump({ provider: 'anthropic' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_fields')
    end

    it 'returns 400 when message is empty string' do
      post '/api/llm/chat', Legion::JSON.dump({ message: '' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_fields')
    end
  end

  # ──────────────────────────────────────────────────────────
  # 201 gateway path (lex-llm-gateway available)
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/llm/chat — gateway path' do
    before do
      stub_llm_started
      stub_const('Legion::Extensions::LLM::Gateway::Runners::Inference', Module.new)

      ingress_mod = Module.new
      stub_const('Legion::Ingress', ingress_mod)
    end

    it 'returns 201 with response when gateway succeeds' do
      fake_result = double('GatewayResult',
                           content:       'gateway response',
                           model:         'claude-sonnet-4-6',
                           input_tokens:  10,
                           output_tokens: 20)
      allow(fake_result).to receive(:respond_to?).with(:content).and_return(true)
      allow(fake_result).to receive(:respond_to?).with(:model).and_return(true)
      allow(fake_result).to receive(:respond_to?).with(:input_tokens).and_return(true)
      allow(fake_result).to receive(:respond_to?).with(:output_tokens).and_return(true)
      allow(fake_result).to receive(:is_a?).with(Hash).and_return(false)

      allow(Legion::Ingress).to receive(:run).and_return({
                                                           success: true,
                                                           result:  fake_result
                                                         })

      post '/api/llm/chat', Legion::JSON.dump({ message: 'via gateway' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(201)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:response]).to eq('gateway response')
      expect(body[:data][:meta][:routed_via]).to eq('gateway')
      expect(body[:data][:meta][:tokens_in]).to eq(10)
    end

    it 'returns 502 when ingress fails' do
      allow(Legion::Ingress).to receive(:run).and_return({
                                                           success: false,
                                                           error:   'runner not found'
                                                         })

      post '/api/llm/chat', Legion::JSON.dump({ message: 'fail test' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(502)
    end

    it 'returns 502 when runner returns nil' do
      allow(Legion::Ingress).to receive(:run).and_return({
                                                           success: true,
                                                           result:  nil,
                                                           status:  'completed'
                                                         })

      post '/api/llm/chat', Legion::JSON.dump({ message: 'nil result' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(502)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error][:code]).to eq('empty_result')
    end

    it 'handles hash result with error' do
      allow(Legion::Ingress).to receive(:run).and_return({
                                                           success: true,
                                                           result:  { error: 'model unavailable' }
                                                         })

      post '/api/llm/chat', Legion::JSON.dump({ message: 'hash error' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(502)
    end

    it 'handles hash result with response key' do
      allow(Legion::Ingress).to receive(:run).and_return({
                                                           success: true,
                                                           result:  { response: 'hash response text' }
                                                         })

      post '/api/llm/chat', Legion::JSON.dump({ message: 'hash response' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(201)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:response]).to eq('hash response text')
    end

    it 'passes correct runner params to Ingress.run' do
      allow(Legion::Ingress).to receive(:run).and_return({ success: true, result: { response: 'ok' } })

      post '/api/llm/chat',
           Legion::JSON.dump({ message: 'test msg', model: 'gpt-4o', provider: 'openai' }),
           'CONTENT_TYPE' => 'application/json'

      expect(Legion::Ingress).to have_received(:run).with(
        hash_including(
          runner_class: 'Legion::Extensions::LLM::Gateway::Runners::Inference',
          function:     'chat',
          source:       'api'
        )
      )
    end
  end

  # ──────────────────────────────────────────────────────────
  # 202 async path (cache available)
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/llm/chat — async path (cache available)' do
    before do
      stub_llm_started
      stub_cache_available
      stub_response_cache
      allow(Legion::LLM::ResponseCache).to receive(:init_request)
    end

    it 'returns 202 with request_id and poll_key' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'hello async' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:request_id)
      expect(body[:data]).to have_key(:poll_key)
    end

    it 'uses client-provided request_id' do
      post '/api/llm/chat',
           Legion::JSON.dump({ message: 'hello', request_id: 'my-custom-id' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:request_id]).to eq('my-custom-id')
    end

    it 'generates a request_id when not provided' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'generate id' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(202)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:request_id]).not_to be_nil
      expect(body[:data][:request_id]).not_to be_empty
    end

    it 'inits the request in ResponseCache' do
      expect(Legion::LLM::ResponseCache).to receive(:init_request).once
      post '/api/llm/chat', Legion::JSON.dump({ message: 'cache init test' }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'spawns background thread that calls ResponseCache.complete' do
      fake_response = double('LLMResponse',
                             content:       'bg response',
                             input_tokens:  3,
                             output_tokens: 7)
      allow(fake_response).to receive(:respond_to?).with(:input_tokens).and_return(true)
      allow(fake_response).to receive(:respond_to?).with(:output_tokens).and_return(true)

      fake_session = double('ChatSession', model: 'claude-sonnet-4-6')
      allow(fake_session).to receive(:ask).and_return(fake_response)
      allow(Legion::LLM).to receive(:chat_direct).and_return(fake_session)

      completed_calls = []
      allow(Legion::LLM::ResponseCache).to receive(:complete) { |id, **| completed_calls << id }

      post '/api/llm/chat', Legion::JSON.dump({ message: 'async thread test' }),
           'CONTENT_TYPE' => 'application/json'

      body = Legion::JSON.load(last_response.body)
      request_id = body[:data][:request_id]

      # Give background thread time to complete
      sleep 0.1

      expect(completed_calls).to include(request_id)
    end

    it 'calls ResponseCache.fail_request if background thread raises' do
      allow(Legion::LLM).to receive(:chat_direct).and_raise(StandardError, 'llm exploded')

      failed_calls = []
      allow(Legion::LLM::ResponseCache).to receive(:fail_request) { |id, **| failed_calls << id }

      post '/api/llm/chat', Legion::JSON.dump({ message: 'error path' }),
           'CONTENT_TYPE' => 'application/json'

      body = Legion::JSON.load(last_response.body)
      request_id = body[:data][:request_id]

      sleep 0.1

      expect(failed_calls).to include(request_id)
    end
  end

  # ──────────────────────────────────────────────────────────
  # 201 synchronous path (cache not available)
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/llm/chat — synchronous path (cache unavailable)' do
    before do
      stub_llm_started
      stub_cache_unavailable
      stub_llm_sync_response
    end

    it 'returns 201 with response body' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'hello sync' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(201)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to have_key(:response)
    end

    it 'includes the LLM response content' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'sync content' }),
           'CONTENT_TYPE' => 'application/json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:response]).to eq('hello from LLM')
    end

    it 'passes model and provider from request body to chat' do
      expect(Legion::LLM).to receive(:chat)
        .with(hash_including(model: 'gpt-4o', provider: 'openai'))
        .and_call_original
      stub_llm_sync_response
      post '/api/llm/chat',
           Legion::JSON.dump({ message: 'direct', model: 'gpt-4o', provider: 'openai' }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'includes meta in response' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'meta check' }),
           'CONTENT_TYPE' => 'application/json'
      body = Legion::JSON.load(last_response.body)
      expect(body[:meta]).to have_key(:timestamp)
      expect(body[:meta][:node]).to eq('test-node')
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/llm/providers — provider health
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/llm/providers' do
    context 'when LLM not started' do
      it 'returns 503' do
        get '/api/llm/providers'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when gateway not loaded' do
      before { stub_llm_started }

      it 'returns 503 with gateway_unavailable' do
        get '/api/llm/providers'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when gateway loaded' do
      let(:stats_mod) do
        Module.new do
          def self.health_report
            [
              { provider: 'anthropic', circuit: 'closed', adjustment: 0, healthy: true },
              { provider: 'openai', circuit: 'open', adjustment: -50, healthy: false }
            ]
          end

          def self.circuit_summary
            { total: 2, closed: 1, open: 1, half_open: 0 }
          end
        end
      end

      before do
        stub_llm_started
        stub_const('Legion::Extensions::LLM::Gateway::Runners::Inference', Module.new)
        stub_const('Legion::Extensions::LLM::Gateway::Runners::ProviderStats', stats_mod)
      end

      it 'returns 200 with providers and summary' do
        get '/api/llm/providers'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:providers].length).to eq(2)
        expect(body[:data][:summary][:total]).to eq(2)
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/llm/providers/:name — single provider detail
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/llm/providers/:name' do
    let(:stats_mod) do
      Module.new do
        def self.provider_detail(provider:)
          { provider: provider.to_s, circuit: 'closed', adjustment: 0, healthy: true }
        end
      end
    end

    before do
      stub_llm_started
      stub_const('Legion::Extensions::LLM::Gateway::Runners::Inference', Module.new)
      stub_const('Legion::Extensions::LLM::Gateway::Runners::ProviderStats', stats_mod)
    end

    it 'returns 200 with provider detail' do
      get '/api/llm/providers/anthropic'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:provider]).to eq('anthropic')
      expect(body[:data][:healthy]).to be true
    end
  end
end
