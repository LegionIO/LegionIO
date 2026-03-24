# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/catalog'
require 'legion/api/llm'

RSpec.describe 'POST /api/llm/chat Tier 0 routing' do
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

  before do
    llm_mod = Module.new do
      def self.started? = true

      def self.chat(**_opts)
        session = Object.new
        session.define_singleton_method(:ask) do |msg|
          response = Object.new
          response.define_singleton_method(:content) { "LLM response to: #{msg}" }
          response.define_singleton_method(:respond_to?) { |m, *| m == :content || super(m) }
          response.define_singleton_method(:input_tokens) { 5 }
          response.define_singleton_method(:output_tokens) { 10 }
          response
        end
        session.define_singleton_method(:model) { 'test-model' }
        session
      end
    end
    stub_const('Legion::LLM', llm_mod)
  end

  context 'when TierRouter returns tier 0' do
    before do
      tier_router = Module.new do
        def self.route(intent:, params: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
          { tier: 0, response: { answer: 'cached response' }, latency_ms: 2, pattern_confidence: 0.95 }
        end
      end
      stub_const('Legion::MCP::TierRouter', tier_router)
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

  context 'when TierRouter returns tier 2' do
    before do
      tier_router = Module.new do
        def self.route(intent:, params: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
          { tier: 2, response: nil, reason: 'no pattern' }
        end
      end
      stub_const('Legion::MCP::TierRouter', tier_router)

      cache_mod = Module.new { def self.connected? = false }
      stub_const('Legion::Cache', cache_mod) unless defined?(Legion::Cache)
      allow(Legion::Cache).to receive(:connected?).and_return(false)
    end

    it 'falls through to normal LLM processing' do
      post '/api/llm/chat', Legion::JSON.dump({ message: 'hello' }),
           { 'CONTENT_TYPE' => 'application/json' }
      expect([200, 201, 202]).to include(last_response.status)
    end
  end
end
