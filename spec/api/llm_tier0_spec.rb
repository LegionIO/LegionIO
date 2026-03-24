# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'POST /api/llm/chat Tier 0 routing' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  context 'when TierRouter returns tier 0' do
    before do
      stub_const('Legion::LLM', Module.new do
        def self.started? = true
      end)
      stub_const('Legion::MCP::TierRouter', Module.new do
        def self.route(**_kwargs)
          { tier: 0, response: { answer: 'cached response' }, latency_ms: 2, pattern_confidence: 0.95 }
        end
      end)
    end

    it 'returns the cached response without calling LLM' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'list workspaces' }),
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:tier]).to eq(0)
      expect(body[:data][:response][:answer]).to eq('cached response')
    end
  end

  context 'when TierRouter returns tier 2 and cache is not available' do
    before do
      stub_const('Legion::LLM', Module.new do
        def self.started? = true

        def self.chat(**_opts)
          session = Object.new
          session.define_singleton_method(:ask) do |msg|
            response = Object.new
            response.define_singleton_method(:content) { "LLM response to: #{msg}" }
            response
          end
          session.define_singleton_method(:model) { 'test-model' }
          session
        end
      end)
      stub_const('Legion::MCP::TierRouter', Module.new do
        def self.route(**_kwargs)
          { tier: 2, response: nil, reason: 'no pattern' }
        end
      end)
    end

    it 'falls through to normal LLM processing' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'hello' }),
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(201)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:response]).to include('LLM response')
    end
  end

  context 'when TierRouter is not defined' do
    before do
      stub_const('Legion::LLM', Module.new do
        def self.started? = true

        def self.chat(**_opts)
          session = Object.new
          session.define_singleton_method(:ask) do |msg|
            response = Object.new
            response.define_singleton_method(:content) { "direct: #{msg}" }
            response
          end
          session.define_singleton_method(:model) { 'test-model' }
          session
        end
      end)
      # Make sure TierRouter is NOT defined
      hide_const('Legion::MCP::TierRouter') if defined?(Legion::MCP::TierRouter)
    end

    it 'goes directly to LLM' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'hello' }),
           { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(201)
    end
  end
end
