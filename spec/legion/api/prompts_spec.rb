# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/prompts'

RSpec.describe 'Prompts API routes' do
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

      register Legion::API::Routes::Prompts
    end
  end

  def app
    test_app
  end

  # ──────────────────────────────────────────────────────────
  # Helper stubs
  # ──────────────────────────────────────────────────────────

  def stub_prompt_client(client)
    app.helpers do
      define_method(:prompt_client) { client }
    end
  end

  def stub_llm_started
    llm_mod = Module.new do
      def self.started? = true
    end
    stub_const('Legion::LLM', llm_mod)
  end

  def stub_llm_sync_response(content: 'LLM output', model_name: 'claude-sonnet-4-6',
                             input_tokens: 8, output_tokens: 12)
    fake_response = double('LLMResponse',
                           content:       content,
                           input_tokens:  input_tokens,
                           output_tokens: output_tokens)
    allow(fake_response).to receive(:respond_to?).with(:input_tokens).and_return(true)
    allow(fake_response).to receive(:respond_to?).with(:output_tokens).and_return(true)

    fake_session = double('ChatSession', model: model_name)
    allow(fake_session).to receive(:ask).and_return(fake_response)
    allow(Legion::LLM).to receive(:chat).and_return(fake_session)
  end

  def build_prompt_client(list: [], get_result: nil, render_result: nil)
    client = double('PromptClient')
    allow(client).to receive(:list_prompts).and_return(list)
    allow(client).to receive(:get_prompt).and_return(get_result) if get_result
    allow(client).to receive(:render_prompt).and_return(render_result) if render_result
    client
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/prompts — list
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/prompts' do
    context 'when lex-prompt is not loaded' do
      before do
        app.helpers do
          define_method(:prompt_client) do
            halt 503, json_error('prompt_unavailable', 'lex-prompt is not loaded', status_code: 503)
          end
        end
      end

      it 'returns 503 with prompt_unavailable code' do
        get '/api/prompts'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('prompt_unavailable')
      end
    end

    context 'when lex-prompt is loaded' do
      before do
        list = [
          { name: 'summarizer', description: 'Summarizes text', latest_version: 2, updated_at: Time.now.utc },
          { name: 'classifier', description: 'Classifies intent', latest_version: 1, updated_at: Time.now.utc }
        ]
        stub_prompt_client(build_prompt_client(list: list))
      end

      it 'returns 200' do
        get '/api/prompts'
        expect(last_response.status).to eq(200)
      end

      it 'returns array of prompts in data' do
        get '/api/prompts'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data].length).to eq(2)
      end

      it 'includes prompt names' do
        get '/api/prompts'
        body = Legion::JSON.load(last_response.body)
        names = body[:data].map { |p| p[:name] }
        expect(names).to include('summarizer', 'classifier')
      end

      it 'includes meta with timestamp and node' do
        get '/api/prompts'
        body = Legion::JSON.load(last_response.body)
        expect(body[:meta]).to have_key(:timestamp)
        expect(body[:meta][:node]).to eq('test-node')
      end
    end

    context 'when list_prompts raises' do
      before do
        client = double('PromptClient')
        allow(client).to receive(:list_prompts).and_raise(StandardError, 'db offline')
        stub_prompt_client(client)
      end

      it 'returns 500 with execution_error' do
        get '/api/prompts'
        expect(last_response.status).to eq(500)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('execution_error')
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # GET /api/prompts/:name — show
  # ──────────────────────────────────────────────────────────

  describe 'GET /api/prompts/:name' do
    context 'when prompt not found' do
      before do
        stub_prompt_client(build_prompt_client(get_result: { error: 'not_found' }))
      end

      it 'returns 404' do
        get '/api/prompts/nonexistent'
        expect(last_response.status).to eq(404)
      end

      it 'returns not_found error code' do
        get '/api/prompts/nonexistent'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('not_found')
      end
    end

    context 'when prompt exists' do
      let(:prompt_data) do
        { name: 'summarizer', version: 2, template: 'Summarize: <%= text %>',
          model_params: { max_tokens: 256 }, content_hash: 'abc123', created_at: Time.now.utc }
      end

      before do
        stub_prompt_client(build_prompt_client(get_result: prompt_data))
      end

      it 'returns 200' do
        get '/api/prompts/summarizer'
        expect(last_response.status).to eq(200)
      end

      it 'includes the prompt name in data' do
        get '/api/prompts/summarizer'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:name]).to eq('summarizer')
      end

      it 'includes the version' do
        get '/api/prompts/summarizer'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:version]).to eq(2)
      end

      it 'includes meta node' do
        get '/api/prompts/summarizer'
        body = Legion::JSON.load(last_response.body)
        expect(body[:meta][:node]).to eq('test-node')
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # POST /api/prompts/:name/run
  # ──────────────────────────────────────────────────────────

  describe 'POST /api/prompts/:name/run' do
    context 'when LLM is not available' do
      it 'returns 503 when Legion::LLM is not defined' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'hello' } }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('llm_unavailable')
      end

      it 'returns 503 when Legion::LLM is defined but not started' do
        llm_mod = Module.new { def self.started? = false }
        stub_const('Legion::LLM', llm_mod)

        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'hello' } }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('llm_unavailable')
      end
    end

    context 'when lex-prompt is not loaded' do
      before do
        stub_llm_started
        app.helpers do
          define_method(:prompt_client) do
            halt 503, json_error('prompt_unavailable', 'lex-prompt is not loaded', status_code: 503)
          end
        end
      end

      it 'returns 503 with prompt_unavailable code' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'hello' } }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(503)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('prompt_unavailable')
      end
    end

    context 'when prompt not found' do
      before do
        stub_llm_started
        stub_prompt_client(build_prompt_client(render_result: { error: 'not_found' }))
      end

      it 'returns 404' do
        post '/api/prompts/missing/run',
             Legion::JSON.dump({ variables: {} }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(404)
      end

      it 'returns not_found error code' do
        post '/api/prompts/missing/run',
             Legion::JSON.dump({ variables: {} }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('not_found')
      end
    end

    context 'when version not found' do
      before do
        stub_llm_started
        stub_prompt_client(build_prompt_client(render_result: { error: 'version_not_found' }))
      end

      it 'returns 422' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {}, version: 99 }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(422)
      end

      it 'returns version_not_found error code' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {}, version: 99 }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('version_not_found')
      end
    end

    context 'when prompt renders and LLM responds' do
      before do
        stub_llm_started
        stub_llm_sync_response(content: 'This is a greeting.', model_name: 'claude-sonnet-4-6',
                               input_tokens: 10, output_tokens: 5)
        stub_prompt_client(build_prompt_client(
                             render_result: { rendered: 'Summarize: Hello world', prompt_version: 3 }
                           ))
      end

      it 'returns 200' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end

      it 'includes the prompt name' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:name]).to eq('summarizer')
      end

      it 'includes the rendered_prompt' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:rendered_prompt]).to eq('Summarize: Hello world')
      end

      it 'includes the LLM response' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:response]).to eq('This is a greeting.')
      end

      it 'includes usage with input and output tokens' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:usage][:input_tokens]).to eq(10)
        expect(body[:data][:usage][:output_tokens]).to eq(5)
      end

      it 'includes the model used' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:model]).to eq('claude-sonnet-4-6')
      end

      it 'includes the version' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:version]).to eq(3)
      end

      it 'passes variables to render_prompt' do
        client = double('PromptClient')
        allow(client).to receive(:render_prompt)
          .with(hash_including(name: 'summarizer', variables: { text: 'Hello world' }))
          .and_return({ rendered: 'Summarize: Hello world', prompt_version: 3 })
        stub_prompt_client(client)

        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: { text: 'Hello world' } }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end

      it 'passes model and provider to chat' do
        expect(Legion::LLM).to receive(:chat)
          .with(hash_including(model: 'claude-opus-4-6', provider: 'bedrock'))
          .and_call_original
        stub_llm_sync_response

        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {}, model: 'claude-opus-4-6', provider: 'bedrock' }),
             'CONTENT_TYPE' => 'application/json'
      end

      it 'includes meta with timestamp and node' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {} }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:meta]).to have_key(:timestamp)
        expect(body[:meta][:node]).to eq('test-node')
      end
    end

    context 'when LLM raises during run' do
      before do
        stub_llm_started
        stub_prompt_client(build_prompt_client(
                             render_result: { rendered: 'Summarize: Hello world', prompt_version: 1 }
                           ))
        allow(Legion::LLM).to receive(:chat).and_raise(StandardError, 'provider timeout')
      end

      it 'returns 500 with execution_error' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {} }),
             'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(500)
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:code]).to eq('execution_error')
      end

      it 'includes the error message' do
        post '/api/prompts/summarizer/run',
             Legion::JSON.dump({ variables: {} }),
             'CONTENT_TYPE' => 'application/json'
        body = Legion::JSON.load(last_response.body)
        expect(body[:error][:message]).to include('provider timeout')
      end
    end

    context 'when body is empty' do
      before do
        stub_llm_started
        stub_llm_sync_response
        stub_prompt_client(build_prompt_client(
                             render_result: { rendered: 'Summarize: ', prompt_version: 1 }
                           ))
      end

      it 'defaults variables to empty hash and succeeds' do
        post '/api/prompts/summarizer/run', '', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end
end
