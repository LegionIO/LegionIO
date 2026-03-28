# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/llm'

RSpec.describe 'LLM inference API route' do
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
      set :raise_errors, false
      set :host_authorization, permitted: :any

      register Legion::API::Routes::Llm
    end
  end

  def app
    test_app
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  def stub_llm_started
    llm_mod = Module.new do
      def self.started? = true
    end
    stub_const('Legion::LLM', llm_mod)
  end

  def stub_llm_chat_session(content: 'inference response', model_name: 'claude-sonnet-4-6',
                            input_tokens: 10, output_tokens: 20)
    fake_response = double('InferenceResponse',
                           content:       content,
                           input_tokens:  input_tokens,
                           output_tokens: output_tokens)
    # Stub all respond_to? checks the endpoint makes — pure doubles need explicit stubs
    allow(fake_response).to receive(:respond_to?).with(:input_tokens).and_return(true)
    allow(fake_response).to receive(:respond_to?).with(:output_tokens).and_return(true)
    allow(fake_response).to receive(:respond_to?).with(:stop_reason).and_return(false)
    allow(fake_response).to receive(:respond_to?).with(:tool_calls).and_return(false)

    model_obj = double('ModelObj', to_s: model_name)

    fake_session = double('ChatSession', model: model_obj)
    allow(fake_session).to receive(:with_tools)
    allow(fake_session).to receive(:add_message)
    allow(fake_session).to receive(:ask).and_return(fake_response)

    allow(Legion::LLM).to receive(:chat).and_return(fake_session)

    [fake_session, fake_response]
  end

  # ── 503 when LLM not started ───────────────────────────────────────────────

  describe 'POST /api/llm/inference — LLM unavailable' do
    it 'returns 503 when Legion::LLM is not defined' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('llm_unavailable')
    end

    it 'returns 503 when Legion::LLM is defined but not started' do
      llm_mod = Module.new { def self.started? = false }
      stub_const('Legion::LLM', llm_mod)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
    end
  end

  # ── 400 when messages missing or invalid ───────────────────────────────────

  describe 'POST /api/llm/inference — validation errors' do
    before { stub_llm_started }

    it 'returns 400 when messages field is absent' do
      post '/api/llm/inference',
           Legion::JSON.dump({ model: 'claude-sonnet-4-6' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('missing_fields')
    end

    it 'returns 400 when messages is not an array' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: 'not an array' }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('invalid_messages')
    end
  end

  # ── 200 success path ───────────────────────────────────────────────────────

  describe 'POST /api/llm/inference — success' do
    before { stub_llm_started }

    it 'returns 200 with content and token counts' do
      stub_llm_chat_session

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:content]).to eq('inference response')
      expect(body[:data][:input_tokens]).to eq(10)
      expect(body[:data][:output_tokens]).to eq(20)
    end

    it 'forwards model and provider to Legion::LLM.chat' do
      fake_session, = stub_llm_chat_session

      expect(Legion::LLM).to receive(:chat).with(
        hash_including(model: 'gpt-4o', provider: 'openai')
      ).and_return(fake_session)

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'test' }],
                               model:    'gpt-4o',
                               provider: 'openai'
                             }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'calls add_message for each message in the history' do
      fake_session, = stub_llm_chat_session

      messages = [
        { role: 'user', content: 'first message' },
        { role: 'assistant', content: 'first response' },
        { role: 'user', content: 'follow up' }
      ]

      expect(fake_session).to receive(:add_message).exactly(3).times

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: messages }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'registers tool declarations when tools are provided' do
      fake_session, = stub_llm_chat_session
      tools_received = []
      allow(fake_session).to receive(:with_tools) { |*args| tools_received.concat(args) }

      tools = [{ name: 'read_file', description: 'Reads a file', parameters: { type: 'object' } }]

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'read main.rb' }],
                               tools:    tools
                             }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(tools_received.length).to eq(1)
      expect(tools_received.first.tool_name).to eq('read_file')
    end

    it 'does not call with_tools when tools array is empty' do
      fake_session, = stub_llm_chat_session
      expect(fake_session).not_to receive(:with_tools)

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'hello' }],
                               tools:    []
                             }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'includes model string in the response' do
      stub_llm_chat_session(model_name: 'claude-sonnet-4-6')

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:model]).to eq('claude-sonnet-4-6')
    end

    it 'includes meta timestamp and node in response wrapper' do
      stub_llm_chat_session

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      body = Legion::JSON.load(last_response.body)
      expect(body[:meta]).to have_key(:timestamp)
      expect(body[:meta][:node]).to eq('test-node')
    end
  end

  # ── 500 error path ─────────────────────────────────────────────────────────

  describe 'POST /api/llm/inference — error handling' do
    before { stub_llm_started }

    it 'returns 500 when LLM.chat raises' do
      allow(Legion::LLM).to receive(:chat).and_raise(StandardError, 'provider exploded')

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'boom' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(500)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error][:code]).to eq('inference_error')
      expect(body[:data][:error][:message]).to eq('provider exploded')
    end
  end
end
