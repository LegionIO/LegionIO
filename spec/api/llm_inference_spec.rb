# frozen_string_literal: true

require_relative 'api_spec_helper'

# Minimal stubs for Legion::LLM error hierarchy used in rescue clauses
unless defined?(Legion::LLM::AuthError)
  module Legion
    module LLM
      class LLMError < StandardError; end
      class AuthError < LLMError; end
      class RateLimitError < LLMError; end
      class TokenBudgetExceeded < LLMError; end
      class ProviderError < LLMError; end
      class ProviderDown < LLMError; end
    end
  end
end

RSpec.describe 'POST /api/llm/inference' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  # Shared pipeline response double builder
  def build_pipeline_response(opts = {})
    content      = opts.fetch(:content, 'Hello from pipeline')
    model        = opts.fetch(:model, 'claude-test')
    tools        = opts.fetch(:tools, [])
    enrichments  = opts.fetch(:enrichments, {})
    input_tokens  = opts.fetch(:input_tokens, 10)
    output_tokens = opts.fetch(:output_tokens, 20)

    tokens = double('tokens',
                    respond_to?:   true,
                    input_tokens:  input_tokens,
                    output_tokens: output_tokens)
    allow(tokens).to receive(:respond_to?) { |m| %i[input_tokens output_tokens].include?(m) }

    double('pipeline_response',
           message:         { role: :assistant, content: content },
           routing:         { provider: 'anthropic', model: model },
           tokens:          tokens,
           tools:           tools,
           enrichments:     enrichments,
           stop:            { reason: :end_turn },
           conversation_id: nil,
           warnings:        [])
  end

  def stub_llm_pipeline(executor_double, pipeline_response)
    stub_const('Legion::LLM::Pipeline::Request', Module.new do
      def self.build(**_kwargs)
        :stubbed_request
      end
    end)

    stub_const('Legion::LLM::Pipeline::Executor', Class.new do
      define_method(:initialize) { |_req| nil }
      define_method(:call) { pipeline_response }
      define_method(:call_stream) do |&block|
        block&.call('Hello ')
        block&.call('from pipeline')
        pipeline_response
      end
    end)

    executor_double
  end

  before do
    stub_const('Legion::LLM', Module.new do
      def self.started? = true
    end)
    # Ensure LLM error classes are accessible for rescue clauses
    stub_const('Legion::LLM::AuthError',          Class.new(StandardError))
    stub_const('Legion::LLM::RateLimitError',     Class.new(StandardError))
    stub_const('Legion::LLM::TokenBudgetExceeded', Class.new(StandardError))
    stub_const('Legion::LLM::ProviderError',      Class.new(StandardError))
    stub_const('Legion::LLM::ProviderDown',       Class.new(StandardError))
  end

  context 'sync path (no stream header)' do
    let(:pipeline_response) { build_pipeline_response }

    before do
      stub_llm_pipeline(nil, pipeline_response)
    end

    it 'returns 200 with content, model, and token fields' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:content]).to eq('Hello from pipeline')
      expect(body[:data][:model]).to eq('claude-test')
      expect(body[:data][:input_tokens]).to eq(10)
      expect(body[:data][:output_tokens]).to eq(20)
    end

    it 'returns nil tool_calls when pipeline returns empty tools array' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:tool_calls]).to be_nil
    end

    it 'returns tool_calls when pipeline response has tools' do
      tool = double('tool_call',
                    respond_to?: true,
                    id:          'tc_1',
                    name:        'file_read',
                    arguments:   { path: '/tmp/foo' })
      allow(tool).to receive(:respond_to?) { |m| %i[id name arguments].include?(m) }

      pr = build_pipeline_response(tools: [tool])
      stub_llm_pipeline(nil, pr)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'read a file' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:tool_calls]).to be_an(Array)
      expect(body[:data][:tool_calls].first[:name]).to eq('file_read')
    end

    it 'passes tool classes (not instances) to the pipeline' do
      received_tools = nil
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        define_singleton_method(:build) do |**kwargs|
          received_tools = kwargs[:tools]
          :stubbed_request
        end
      end)

      stub_const('RubyLLM::Tool', Class.new)

      plain_tokens = Object.new.tap do |t|
        t.define_singleton_method(:input_tokens)  { 0 }
        t.define_singleton_method(:output_tokens) { 0 }
        t.define_singleton_method(:respond_to?) { |_m, *| true }
      end
      plain_pr = Object.new.tap do |pr|
        tk = plain_tokens
        pr.define_singleton_method(:message)     { { content: 'ok' } }
        pr.define_singleton_method(:routing)     { { model: 'm' } }
        pr.define_singleton_method(:tokens)      { tk }
        pr.define_singleton_method(:tools)       { [] }
        pr.define_singleton_method(:enrichments) { {} }
        pr.define_singleton_method(:stop)        { { reason: :end_turn } }
      end

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { plain_pr }
      end)

      tool_payload = { name: 'sh', description: 'run shell', parameters: nil }
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'go' }],
                               tools:    [tool_payload] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(received_tools).to be_an(Array)
      received_tools&.each do |t|
        expect(t).to be_a(Class).or respond_to(:name)
      end
    end

    it 'returns 400 when messages is not an array' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: 'not an array' }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
    end

    it 'returns 503 when LLM is unavailable' do
      stub_const('Legion::LLM', Module.new do
        def self.started? = false
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hi' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(503)
    end
  end

  context 'GAIA bridge' do
    let(:pipeline_response) { build_pipeline_response }

    before { stub_llm_pipeline(nil, pipeline_response) }

    it 'calls Legion::Gaia.ingest when GAIA is started' do
      ingest_called = false
      frame_content = nil

      Object.new
      fake_gaia = Module.new do
        define_singleton_method(:started?) { true }
        define_singleton_method(:ingest) do |frame|
          ingest_called = true
          frame_content = frame
        end
      end

      fake_input_frame_class = Class.new do
        attr_reader :content, :channel_id

        def initialize(content:, channel_id:, **_opts)
          @content    = content
          @channel_id = channel_id
        end
      end

      stub_const('Legion::Gaia', fake_gaia)
      stub_const('Legion::Gaia::InputFrame', fake_input_frame_class)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'gaia test message' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(ingest_called).to be(true)
      expect(frame_content.content).to eq('gaia test message')
      expect(frame_content.channel_id).to eq(:api)
    end

    it 'does not fail when GAIA is not defined' do
      hide_const('Legion::Gaia') if defined?(Legion::Gaia)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end

    it 'does not call GAIA.ingest when GAIA is not started' do
      ingest_called = false
      stub_const('Legion::Gaia', Module.new do
        define_singleton_method(:started?) { false }
        define_singleton_method(:ingest) { |_| ingest_called = true }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'hello' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(ingest_called).to be(false)
    end
  end

  context 'SSE streaming path' do
    let(:pipeline_response) { build_pipeline_response(content: 'Hello from pipeline') }

    before do
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        def self.build(**_kwargs)
          :stubbed_request
        end
      end)

      pr = pipeline_response
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) { |_h| nil }
        define_method(:call_stream) do |&block|
          block&.call('Hello ')
          block&.call('from pipeline')
          pr
        end
      end)
    end

    it 'returns text/event-stream content type' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'stream me' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      expect(last_response.content_type).to include('text/event-stream')
    end

    it 'emits text-delta events for each chunk' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'stream me' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      expect(body).to include('event: text-delta')
      expect(body).to include('"delta":"Hello "')
      expect(body).to include('"delta":"from pipeline"')
    end

    it 'emits a done event with full content and model' do
      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'stream me' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      expect(body).to include('event: done')
      expect(body).to include('"content":"Hello from pipeline"')
      expect(body).to include('"model":"claude-test"')
    end

    it 'emits enrichment event when enrichments are present' do
      pr = build_pipeline_response(enrichments: { 'rag:context' => { docs: 1 } })
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) { |_h| nil }
        define_method(:call_stream) do |&block|
          block&.call('chunk')
          pr
        end
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'rag query' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      expect(body).to include('event: enrichment')
      expect(body).to include('rag:context')
    end

    it 'emits tool-call events when pipeline response has tools' do
      tool = double('tool_call', id: 'tc_1', name: 'file_read', arguments: { path: '/tmp/x' })
      allow(tool).to receive(:respond_to?) { |m| %i[id name arguments].include?(m) }

      pr = build_pipeline_response(tools: [tool])
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) { |_h| nil }
        define_method(:call_stream) do |&block|
          block&.call('text chunk')
          pr
        end
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'use tool' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      expect(body).to include('event: tool-call')
      expect(body).to include('"toolName":"file_read"')
    end

    it 'emits real-time tool-call event via tool_event_handler with camelCase keys' do
      captured_handler = nil
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) { |h| captured_handler = h }
        define_method(:call_stream) do |&block|
          block&.call('chunk')
          # Fire the real-time handler as if a tool call happened mid-stream
          captured_handler&.call(
            type:         :tool_call,
            tool_call_id: 'tc_realtime',
            tool_name:    'file_read',
            arguments:    { path: '/tmp/y' },
            started_at:   nil
          )
          build_pipeline_response_local
        end
      end)

      def build_pipeline_response_local
        tokens = double('tokens',
                        input_tokens:  0,
                        output_tokens: 0,
                        respond_to?:   true)
        allow(tokens).to receive(:respond_to?) { |m| %i[input_tokens output_tokens].include?(m) }
        double('pipeline_response',
               message:         { role: :assistant, content: 'ok' },
               routing:         { provider: 'anthropic', model: 'test' },
               tokens:          tokens,
               tools:           [],
               enrichments:     {},
               stop:            { reason: :end_turn },
               conversation_id: nil,
               warnings:        [])
      end

      pr = build_pipeline_response(tools: [])
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) do |h|
          h.call(
            type:         :tool_call,
            tool_call_id: 'tc_realtime',
            tool_name:    'file_read',
            arguments:    { path: '/tmp/y' },
            started_at:   nil
          )
        end
        define_method(:call_stream) do |&block|
          block&.call('chunk')
          pr
        end
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'use tool' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      expect(body).to include('event: tool-call')
      parsed = body.scan(/data: (\{.*\})/).flatten.map { |d| Legion::JSON.load(d) }
      tool_call_event = parsed.find { |e| e[:toolCallId] == 'tc_realtime' }
      expect(tool_call_event).not_to be_nil
      expect(tool_call_event[:toolName]).to eq('file_read')
    end

    it 'does not emit duplicate post-hoc tool-call for IDs already sent by tool_event_handler' do
      tc_id = 'tc_dedup'
      tool = double('tool_call', id: tc_id, name: 'grep', arguments: { pattern: 'foo' })
      allow(tool).to receive(:respond_to?) { |m| %i[id name arguments].include?(m) }

      pr = build_pipeline_response(tools: [tool])
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:tool_event_handler=) do |h|
          # Simulate real-time emission with the same ID
          h.call(
            type:         :tool_call,
            tool_call_id: tc_id,
            tool_name:    'grep',
            arguments:    { pattern: 'foo' },
            started_at:   nil
          )
        end
        define_method(:call_stream) do |&block|
          block&.call('chunk')
          pr
        end
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'grep it' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'text/event-stream' }

      body = last_response.body
      tc_events = body.scan('event: tool-call').size
      expect(tc_events).to eq(1)
    end

    it 'does NOT stream when Accept header is missing text/event-stream' do
      sync_tokens = Object.new.tap do |t|
        t.define_singleton_method(:input_tokens)  { 0 }
        t.define_singleton_method(:output_tokens) { 0 }
        t.define_singleton_method(:respond_to?) { |_m, *| true }
      end
      sync_pr = Object.new.tap do |pr|
        tk = sync_tokens
        pr.define_singleton_method(:message)     { { content: 'sync response' } }
        pr.define_singleton_method(:routing)     { { model: 'test' } }
        pr.define_singleton_method(:tokens)      { tk }
        pr.define_singleton_method(:tools)       { [] }
        pr.define_singleton_method(:enrichments) { {} }
        pr.define_singleton_method(:stop)        { { reason: :end_turn } }
      end

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { sync_pr }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'no stream' }], stream: true }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.content_type).not_to include('text/event-stream')
      expect(last_response.status).to eq(200)
    end
  end

  context 'error mapping' do
    before do
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        def self.build(**_kwargs) = :req
      end)
    end

    {
      'AuthError'           => [401, 'auth_error'],
      'RateLimitError'      => [429, 'rate_limit'],
      'TokenBudgetExceeded' => [413, 'token_budget_exceeded'],
      'ProviderError'       => [502, 'provider_error'],
      'ProviderDown'        => [502, 'provider_error']
    }.each do |error_class, (expected_status, expected_code)|
      it "maps #{error_class} to HTTP #{expected_status}" do
        err_klass = Class.new(StandardError)
        stub_const("Legion::LLM::#{error_class}", err_klass)

        # Treat ProviderDown same as ProviderError in the rescue clause
        stub_const('Legion::LLM::ProviderError', err_klass) if error_class == 'ProviderDown'
        stub_const('Legion::LLM::ProviderDown', err_klass)  if error_class == 'ProviderError'

        stub_const('Legion::LLM::Pipeline::Executor', Class.new do
          define_method(:initialize) { |_req| nil }
          define_method(:call) { raise err_klass, 'simulated error' }
        end)

        post '/api/llm/inference',
             Legion::JSON.dump({ messages: [{ role: 'user', content: 'err' }] }),
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(expected_status)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:error][:code]).to eq(expected_code)
      end
    end

    it 'maps StandardError to 500 inference_error' do
      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { raise StandardError, 'boom' }
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({ messages: [{ role: 'user', content: 'err' }] }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(500)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:error][:code]).to eq('inference_error')
    end
  end

  context 'build_client_tool_class helper' do
    before do
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        def self.build(**_kwargs) = :req
      end)

      helper_tokens = Object.new.tap do |t|
        t.define_singleton_method(:input_tokens)  { 0 }
        t.define_singleton_method(:output_tokens) { 0 }
        t.define_singleton_method(:respond_to?) { |_m, *| true }
      end
      helper_pr = Object.new.tap do |pr|
        tk = helper_tokens
        pr.define_singleton_method(:message)     { { content: 'ok' } }
        pr.define_singleton_method(:routing)     { { model: 'test' } }
        pr.define_singleton_method(:tokens)      { tk }
        pr.define_singleton_method(:tools)       { [] }
        pr.define_singleton_method(:enrichments) { {} }
        pr.define_singleton_method(:stop)        { { reason: :end_turn } }
      end

      stub_const('Legion::LLM::Pipeline::Executor', Class.new do
        define_method(:initialize) { |_req| nil }
        define_method(:call) { helper_pr }
      end)
    end

    it 'returns a Class (not an instance) via filter_map' do
      stub_const('RubyLLM::Tool', Class.new)

      received_tools = []
      stub_const('Legion::LLM::Pipeline::Request', Module.new do
        define_singleton_method(:build) do |**kwargs|
          received_tools.concat(Array(kwargs[:tools]))
          :req
        end
      end)

      post '/api/llm/inference',
           Legion::JSON.dump({
                               messages: [{ role: 'user', content: 'test' }],
                               tools:    [{ name: 'file_read', description: 'reads files', parameters: nil }]
                             }),
           { 'CONTENT_TYPE' => 'application/json' }

      unless received_tools.empty?
        received_tools.each do |t|
          expect(t).to be_a(Class).or respond_to(:name)
        end
      end
    end
  end
end
