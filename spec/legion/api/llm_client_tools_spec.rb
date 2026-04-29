# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'sinatra/base'
require 'legion/api/helpers'
require 'legion/api/validators'
require 'legion/api/llm'

RSpec.describe 'LLM API client tool dispatch (web_fetch / web_search)' do
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

  before do
    stub_const('RubyLLM::Tool', Class.new do
      def self.description(*); end
      def self.params(*); end
    end)
  end

  # Helper to access the private build_client_tool_class helper defined on the Sinatra app
  def build_tool(name, description = 'test tool', schema = nil)
    test_app.new!.instance_eval { build_client_tool_class(name, description, schema) }
  end

  it 'skips client tool construction when RubyLLM tool base is unavailable' do
    app_instance = test_app.new!
    allow(app_instance).to receive(:ruby_llm_tool_base).and_return(nil)

    expect(app_instance.instance_eval { build_client_tool_class('web_fetch', 'test tool', nil) }).to be_nil
  end

  # ──────────────────────────────────────────────────────────
  # web_fetch
  # ──────────────────────────────────────────────────────────

  describe 'web_fetch client tool' do
    before do
      require 'legion/cli/chat/web_fetch'
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return('# Example Page\n\nSome content here.')
      # Stub DNS resolution so specs don't hit the network and bypass SSRF guard
      allow(Resolv).to receive(:getaddress).and_return('93.184.216.34')
    end

    it 'delegates to WebFetch.fetch' do
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com')
      expect(Legion::CLI::Chat::WebFetch).to have_received(:fetch).with('https://example.com')
      expect(result).to eq('# Example Page\n\nSome content here.')
    end

    it 'falls back to first kwarg value when :url is missing' do
      klass = build_tool('web_fetch')
      klass.new.execute(uri: 'https://fallback.com')
      expect(Legion::CLI::Chat::WebFetch).to have_received(:fetch).with('https://fallback.com')
    end

    it 'honors maxLength by truncating the result' do
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return('A' * 200)
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com', maxLength: 50)
      expect(result.length).to eq(50)
    end

    it 'honors max_length (snake_case variant)' do
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return('B' * 200)
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com', max_length: 100)
      expect(result.length).to eq(100)
    end

    it 'returns full content when maxLength is not specified' do
      long_content = 'C' * 500
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return(long_content)
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com')
      expect(result.length).to eq(500)
    end

    it 'treats zero maxLength as no-op (returns full content)' do
      long_content = 'D' * 300
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return(long_content)
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com', maxLength: 0)
      expect(result.length).to eq(300)
    end

    it 'treats negative maxLength as no-op (returns full content)' do
      long_content = 'E' * 300
      allow(Legion::CLI::Chat::WebFetch).to receive(:fetch).and_return(long_content)
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://example.com', maxLength: -10)
      expect(result.length).to eq(300)
    end

    it 'returns a Tool error for private IP addresses (SSRF guard)' do
      allow(Resolv).to receive(:getaddress).and_return('192.168.1.1')
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://internal.example.com')
      expect(result).to start_with('Tool error:')
      expect(Legion::CLI::Chat::WebFetch).not_to have_received(:fetch)
    end

    it 'returns a Tool error for loopback addresses (SSRF guard)' do
      allow(Resolv).to receive(:getaddress).and_return('127.0.0.1')
      klass = build_tool('web_fetch')
      result = klass.new.execute(url: 'https://localhost')
      expect(result).to start_with('Tool error:')
      expect(Legion::CLI::Chat::WebFetch).not_to have_received(:fetch)
    end
  end

  # ──────────────────────────────────────────────────────────
  # web_search
  # ──────────────────────────────────────────────────────────

  describe 'web_search client tool' do
    let(:search_results) do
      {
        query:           'ruby gems',
        results:         [
          { title: 'RubyGems.org', url: 'https://rubygems.org', snippet: 'Find, install, and publish gems.' },
          { title: 'Ruby-lang', url: 'https://ruby-lang.org', snippet: 'The Ruby programming language.' }
        ],
        fetched_content: nil
      }
    end

    before do
      require 'legion/cli/chat/web_search'
      allow(Legion::CLI::Chat::WebSearch).to receive(:search).and_return(search_results)
    end

    it 'delegates to WebSearch.search' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'ruby gems')
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('ruby gems', max_results: 5, auto_fetch: false)
    end

    it 'formats results as markdown sections' do
      klass = build_tool('web_search')
      result = klass.new.execute(query: 'ruby gems')
      expect(result).to include('### RubyGems.org')
      expect(result).to include('https://rubygems.org')
      expect(result).to include('### Ruby-lang')
      expect(result).to include('https://ruby-lang.org')
    end

    it 'does not return the generic "not executable server-side" error' do
      klass = build_tool('web_search')
      result = klass.new.execute(query: 'test query')
      expect(result).not_to include('not executable server-side')
    end

    it 'passes max_results to the search' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'test', max_results: 3)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('test', max_results: 3, auto_fetch: false)
    end

    it 'accepts maxResults (camelCase variant)' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'test', maxResults: 8)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('test', max_results: 8, auto_fetch: false)
    end

    it 'falls back to first kwarg value when :query is missing' do
      klass = build_tool('web_search')
      klass.new.execute(q: 'fallback query')
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('fallback query', max_results: 5, auto_fetch: false)
    end

    it 'defaults to 5 when max_results is 0' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'test', max_results: 0)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('test', max_results: 5, auto_fetch: false)
    end

    it 'defaults to 5 when max_results is negative' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'test', max_results: -3)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('test', max_results: 5, auto_fetch: false)
    end

    it 'caps max_results at 50' do
      klass = build_tool('web_search')
      klass.new.execute(query: 'test', max_results: 999)
      expect(Legion::CLI::Chat::WebSearch).to have_received(:search)
        .with('test', max_results: 50, auto_fetch: false)
    end
  end
end
