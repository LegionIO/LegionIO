# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/graph/builder'

RSpec.describe 'Workflow API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/relationships/graph' do
    context 'when data is not connected' do
      it 'returns 503' do
        get '/api/relationships/graph'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when data is connected' do
      before do
        Legion::Settings.loader.settings[:data] = { connected: true }
      end

      after do
        Legion::Settings.loader.settings[:data] = { connected: false }
      end

      it 'returns nodes and edges' do
        allow(Legion::Graph::Builder).to receive(:build).and_return({
                                                                      nodes: {
                                                                        'lex-audit.write' => { label: 'lex-audit.write', type: 'trigger' },
                                                                        'lex-data.store'  => { label: 'lex-data.store', type: 'action' }
                                                                      },
                                                                      edges: [{ from: 'lex-audit.write', to: 'lex-data.store', label: 'persist',
chain_id: nil }]
                                                                    })

        get '/api/relationships/graph'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:nodes]).to be_an(Array)
        expect(body[:data][:edges]).to be_an(Array)
        expect(body[:data][:nodes].size).to eq(2)
        expect(body[:data][:edges].size).to eq(1)
      end

      it 'returns empty graph when no relationships exist' do
        allow(Legion::Graph::Builder).to receive(:build).and_return({ nodes: {}, edges: [] })

        get '/api/relationships/graph'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:nodes]).to eq([])
        expect(body[:data][:edges]).to eq([])
      end

      it 'filters by extension parameter' do
        allow(Legion::Graph::Builder).to receive(:build).and_return({
                                                                      nodes: {
                                                                        'lex-audit.write' => { label: 'lex-audit.write', type: 'trigger' },
                                                                        'lex-data.store'  => { label: 'lex-data.store', type: 'action' }
                                                                      },
                                                                      edges: [{ from: 'lex-audit.write', to: 'lex-data.store', label: 'persist',
chain_id: nil }]
                                                                    })

        get '/api/relationships/graph', extension: 'lex-audit'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        node_ids = body[:data][:nodes].map { |n| n[:id] }
        expect(node_ids).to include('lex-audit.write')
      end
    end
  end
end
