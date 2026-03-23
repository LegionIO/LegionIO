# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/worker_status'

RSpec.describe Legion::CLI::Chat::Tools::WorkerStatus do
  subject(:tool) { described_class.new }

  let(:stub_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(stub_http)
    allow(stub_http).to receive(:open_timeout=)
    allow(stub_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'with list action' do
      let(:body) do
        '{"data":[{"worker_id":"w-1","name":"Sync Bot","lifecycle_state":"active","risk_tier":"low"}]}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns formatted worker list' do
        result = tool.execute
        expect(result).to include('Digital Workers (1)')
        expect(result).to include('w-1')
        expect(result).to include('Sync Bot')
        expect(result).to include('active')
      end
    end

    context 'with empty worker list' do
      before do
        response = instance_double(Net::HTTPResponse, body: '{"data":[]}')
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns no workers message' do
        result = tool.execute
        expect(result).to eq('No digital workers found.')
      end
    end

    context 'with status filter' do
      let(:body) { '{"data":[{"worker_id":"w-1","name":"Bot","lifecycle_state":"paused","risk_tier":"low"}]}' }

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'passes the filter to the API' do
        tool.execute(status_filter: 'paused')
        expect(stub_http).to have_received(:get).with('/api/workers?lifecycle_state=paused')
      end
    end

    context 'with show action' do
      let(:body) do
        '{"data":{"worker_id":"w-1","name":"Sync Bot","lifecycle_state":"active","risk_tier":"low","team":"ops"}}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns worker details' do
        result = tool.execute(action: 'show', worker_id: 'w-1')
        expect(result).to include('Worker: w-1')
        expect(result).to include('name: Sync Bot')
        expect(result).to include('team: ops')
      end

      it 'requires worker_id' do
        result = tool.execute(action: 'show')
        expect(result).to include('worker_id is required')
      end
    end

    context 'with health action' do
      let(:all_body) do
        '{"data":[' \
          '{"worker_id":"w-1","lifecycle_state":"active","health_status":"healthy"},' \
          '{"worker_id":"w-2","lifecycle_state":"active","health_status":"unhealthy","name":"Bad Bot"},' \
          '{"worker_id":"w-3","lifecycle_state":"paused","health_status":"healthy"}]}'
      end
      let(:unhealthy_body) do
        '{"data":[{"worker_id":"w-2","name":"Bad Bot","health_status":"unhealthy"}]}'
      end

      before do
        unhealthy_resp = instance_double(Net::HTTPResponse, body: unhealthy_body)
        all_resp = instance_double(Net::HTTPResponse, body: all_body)
        allow(stub_http).to receive(:get).and_return(unhealthy_resp, all_resp)
      end

      it 'returns health summary' do
        result = tool.execute(action: 'health')
        expect(result).to include('Worker Health Summary')
        expect(result).to include('Total:     3')
        expect(result).to include('Active:    2')
        expect(result).to include('Paused:    1')
        expect(result).to include('Unhealthy: 1')
        expect(result).to include('w-2')
      end
    end

    context 'when daemon is not running' do
      before do
        allow(stub_http).to receive(:get).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns daemon not running message' do
        result = tool.execute
        expect(result).to include('daemon not running')
      end
    end
  end
end
