# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Org Chart API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'GET /api/org-chart' do
    context 'when data is not connected' do
      it 'returns 503' do
        get '/api/org-chart'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when data is connected' do
      let(:extension_model) { double('Legion::Data::Model::Extension') }
      let(:function_model) { double('Legion::Data::Model::Function') }
      let(:worker_model) { double('Legion::Data::Model::DigitalWorker') }

      before do
        stub_const('Legion::Data::Model::Extension', extension_model)
        stub_const('Legion::Data::Model::Function', function_model)
        stub_const('Legion::Data::Model::DigitalWorker', worker_model)
        Legion::Settings.loader.settings[:data] = { connected: true }
      end

      after do
        Legion::Settings.loader.settings[:data] = { connected: false }
      end

      it 'returns a departments structure' do
        ext = double('ext', id: 1, name: 'lex-audit')
        func = double('func', name: 'audit.write')
        worker = double('worker', id: 1, name: 'audit-bot', lifecycle_state: 'active', extension_name: 'lex-audit')

        allow(extension_model).to receive(:all).and_return([ext])
        allow(function_model).to receive(:where).with(extension_id: 1).and_return(double(all: [func]))
        allow(worker_model).to receive(:all).and_return([worker])

        get '/api/org-chart'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:departments]).to be_an(Array)
        expect(body[:data][:departments].first[:name]).to eq('lex-audit')
      end

      it 'returns empty departments when no extensions exist' do
        allow(extension_model).to receive(:all).and_return([])
        allow(worker_model).to receive(:all).and_return([])

        get '/api/org-chart'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:departments]).to eq([])
      end
    end
  end
end
