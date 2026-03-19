# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Routes::ExtensionCatalog' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    Legion::Extensions::Catalog.reset!
    Legion::Extensions::Catalog.register('lex-detect', state: :running)
    Legion::Extensions::Catalog.register('lex-node', state: :loaded)
  end

  describe 'GET /api/catalog' do
    it 'returns all catalog entries' do
      get '/api/catalog'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].size).to eq(2)
    end
  end

  describe 'GET /api/catalog/:name' do
    it 'returns a single extension manifest' do
      get '/api/catalog/lex-detect'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:name]).to eq('lex-detect')
      expect(body[:data][:state]).to eq('running')
    end

    it 'returns 404 for unknown extension' do
      get '/api/catalog/lex-nonexistent'
      expect(last_response.status).to eq(404)
    end
  end
end
