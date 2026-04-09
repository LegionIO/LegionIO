# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Extensions API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    Legion::Extensions::Catalog.reset!
    Legion::Extensions::Catalog.register('lex-example', state: :running)
    Legion::Extensions::Catalog.transition('lex-example', :running)
    allow(Legion::Extensions).to receive(:loaded_extension_modules).and_return([])
  end

  describe 'GET /api/extensions' do
    it 'returns 200 with catalog entries' do
      get '/api/extensions'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data]).to be_an(Array)
    end
  end

  describe 'GET /api/extensions/:name' do
    it 'returns 404 when extension is not in catalog' do
      get '/api/extensions/lex-nonexistent'
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /api/extensions/:name/runners/:runner_name/functions/:func_name/invoke' do
    it 'returns 404 when extension is not in catalog' do
      post '/api/extensions/lex-nonexistent/runners/foo/functions/bar/invoke',
           '{}', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(404)
    end
  end
end
