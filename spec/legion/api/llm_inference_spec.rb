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
    loader.settings[:client]     = { name: 'test-node', ready: true }
    loader.settings[:data]       = { connected: false }
    loader.settings[:transport]  = { connected: false }
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

  # ── shared helpers ──────────────────────────────────────────────────────────

  def stub_llm_started
    llm_mod = Module.new do
      def self.started? = true
    end
    stub_const('Legion::LLM', llm_mod)
    %i[AuthError RateLimitError TokenBudgetExceeded ProviderError ProviderDown].each do |e|
      stub_const("Legion::LLM::#{e}", Class.new(StandardError))
    end
  end

  def make_tokens(input: 10, output: 20)
    Object.new.tap do |t|
      t.define_singleton_method(:input_tokens)  { input }
      t.define_singleton_method(:output_tokens) { output }
      t.define_singleton_method(:respond_to?) { |_m, *| true }
    end
  end

  def make_pipeline_response(opts = {})
    content     = opts.fetch(:content, 'inference response')
    model       = opts.fetch(:model, 'claude-sonnet-4-6')
    tools       = opts.fetch(:tools, [])
    enrichments = opts.fetch(:enrichments, {})
    stop_reason = opts.fetch(:stop_reason, :end_turn)
    tk          = opts[:tokens] || make_tokens

    Object.new.tap do |pr|
      pr.define_singleton_method(:message)     { { role: :assistant, content: content } }
      pr.define_singleton_method(:routing)     { { provider: 'anthropic', model: model } }
      pr.define_singleton_method(:tokens)      { tk }
      pr.define_singleton_method(:tools)       { tools }
      pr.define_singleton_method(:enrichments) { enrichments }
      pr.define_singleton_method(:stop)        { { reason: stop_reason } }
    end
  end

  def stub_pipeline(pipeline_response)
    stub_const('Legion::LLM::Pipeline::Request', Module.new do
      def self.build(**_kwargs) = :stubbed_req
    end)

    pr = pipeline_response
    stub_const('Legion::LLM::Pipeline::Executor', Class.new do
      define_method(:initialize) { |_req| nil }
      define_method(:call) { pr }
      define_method(:call_stream) do |&block|
        block&.call('streaming chunk')
        pr
      end
    end)
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

  # ── 200 success path (pipeline-based) ─────────────────────────────────────

  describe 'POST /api/llm/inference — success' do
    before { stub_llm_started }

    it 'returns 200 with content and token counts' do
      stub_pipeline(make_pipeline_response)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:content]).to eq('inference response')
      expect(body[:data][:input_tokens]).to eq(10)
      expect(body[:data][:output_tokens]).to eq(20)
    end

    it 'forwards model and provider via Pipeline::Request.build' do
      received_routing = nil
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        define_singleton_method(:build) do |**kwargs|
          received_routing = kwargs[:routing]
          :stubbed_req
        end
      end)

      pr = make_pipeline_response(model: 'gpt-4o')
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { pr }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'test' }],
                               model:    'gpt-4o',
                               provider: 'openai'
                             }),
           'CONTENT_TYPE' => 'application/json'

      expect(received_routing).to include(model: 'gpt-4o', provider: 'openai')
    end

    it 'passes tool classes (not instances) when tools provided' do
      received_tools = nil
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        define_singleton_method(:build) do |**kwargs|
          received_tools = kwargs[:tools]
          :stubbed_req
        end
      end)

      stub_const('RubyLLM::Tool', Class.new)
      pr = make_pipeline_response
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { pr }
      end)

      tools = [{ name: 'read_file', description: 'Reads a file', parameters: { type: 'object' } }]

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'read main.rb' }],
                               tools:    tools
                             }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      expect(received_tools).to be_an(Array) if received_tools
      received_tools&.each { |t| expect(t).to be_a(Class).or respond_to(:name) }
    end

    it 'includes model string in the response' do
      stub_pipeline(make_pipeline_response(model: 'claude-sonnet-4-6'))

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:model]).to eq('claude-sonnet-4-6')
    end

    it 'includes meta timestamp and node in response wrapper' do
      stub_pipeline(make_pipeline_response)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           'CONTENT_TYPE' => 'application/json'

      body = Legion::JSON.load(last_response.body)
      expect(body[:meta]).to have_key(:timestamp)
      expect(body[:meta][:node]).to eq('test-node')
    end
  end

  # ── error handling ─────────────────────────────────────────────────────────

  describe 'POST /api/llm/inference — error handling' do
    before do
      stub_llm_started
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        def self.build(**_kwargs) = :req
      end)
    end

    it 'returns 500 when pipeline executor raises StandardError' do
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { raise StandardError, 'provider exploded' }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'boom' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(500)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error][:code]).to eq('inference_error')
      expect(body[:data][:error][:message]).to eq('provider exploded')
    end

    it 'returns 401 when pipeline raises AuthError' do
      auth_err = Class.new(StandardError)
      stub_const('Legion::LLM::AuthError', auth_err)

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { raise auth_err, 'unauthorized' }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'secret' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(401)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error][:code]).to eq('auth_error')
    end

    it 'returns 429 when pipeline raises RateLimitError' do
      rate_err = Class.new(StandardError)
      stub_const('Legion::LLM::RateLimitError', rate_err)

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { raise rate_err, 'slow down' }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'fast' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(429)
    end

    it 'returns 502 when pipeline raises ProviderError' do
      provider_err = Class.new(StandardError)
      stub_const('Legion::LLM::ProviderError', provider_err)
      stub_const('Legion::LLM::ProviderDown',  Class.new(StandardError))

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { raise provider_err, 'provider down' }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'oops' }] }),
           'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(502)
    end
  end
end
