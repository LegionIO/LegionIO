# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Workers Health API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:worker_id) { 'w-health-123' }
  let(:worker_model) { class_double('Legion::Data::Model::DigitalWorker') }
  let(:node_model) { class_double('Legion::Data::Model::Node') }
  let(:worker) do
    double('worker',
           worker_id:         worker_id,
           health_status:     'online',
           last_heartbeat_at: Time.now,
           health_node:       'test-node',
           values:            { worker_id: worker_id, health_status: 'online' })
  end

  describe 'GET /api/workers/:id/health' do
    context 'when data is not connected' do
      it 'returns 503' do
        get "/api/workers/#{worker_id}/health"
        expect(last_response.status).to eq(503)
      end
    end

    context 'when data is connected' do
      before do
        stub_const('Legion::Data::Model::DigitalWorker', worker_model)
        stub_const('Legion::Data::Model::Node', node_model)
        Legion::Settings.loader.settings[:data] = { connected: true }
      end

      after do
        Legion::Settings.loader.settings[:data] = { connected: false }
      end

      it 'returns health details for an existing worker' do
        allow(worker_model).to receive(:first).with(worker_id: worker_id).and_return(worker)
        node = double('node', parsed_metrics: { memory_rss_mb: 142 })
        allow(node_model).to receive(:[]).with(name: 'test-node').and_return(node)

        get "/api/workers/#{worker_id}/health"
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:health_status]).to eq('online')
        expect(body[:data][:health_node]).to eq('test-node')
        expect(body[:data][:node_metrics][:memory_rss_mb]).to eq(142)
      end

      it 'returns 404 for unknown worker' do
        allow(worker_model).to receive(:first).with(worker_id: 'unknown').and_return(nil)

        get '/api/workers/unknown/health'
        expect(last_response.status).to eq(404)
      end

      it 'returns nil node_metrics when worker has no health_node' do
        offline_worker = double('worker',
                                worker_id:         worker_id,
                                health_status:     'unknown',
                                last_heartbeat_at: nil,
                                health_node:       nil,
                                values:            { worker_id: worker_id, health_status: 'unknown' })
        allow(worker_model).to receive(:first).with(worker_id: worker_id).and_return(offline_worker)

        get "/api/workers/#{worker_id}/health"
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data][:node_metrics]).to be_nil
      end
    end
  end

  describe 'GET /api/workers?health_status=online' do
    context 'when data is connected' do
      let(:dataset) { double('dataset') }

      before do
        stub_const('Legion::Data::Model::DigitalWorker', worker_model)
        Legion::Settings.loader.settings[:data] = { connected: true }
      end

      after do
        Legion::Settings.loader.settings[:data] = { connected: false }
      end

      it 'filters workers by health_status' do
        allow(worker_model).to receive(:order).with(:id).and_return(dataset)
        allow(dataset).to receive(:where).with(health_status: 'online').and_return(dataset)
        allow(dataset).to receive(:count).and_return(1)
        allow(dataset).to receive(:limit).and_return(dataset)
        allow(dataset).to receive(:all).and_return([worker])

        get '/api/workers?health_status=online'
        expect(last_response.status).to eq(200)
        body = Legion::JSON.load(last_response.body)
        expect(body[:data]).to be_an(Array)
      end
    end
  end
end
