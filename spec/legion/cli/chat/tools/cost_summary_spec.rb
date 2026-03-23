# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/cost_summary'

RSpec.describe Legion::CLI::Chat::Tools::CostSummary do
  subject(:tool) { described_class.new }

  let(:stub_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(stub_http)
    allow(stub_http).to receive(:open_timeout=)
    allow(stub_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'with summary action' do
      let(:summary_body) do
        '{"data":{"today":0.1234,"week":0.5678,"month":1.9012,"workers":3}}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: summary_body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns formatted cost summary' do
        result = tool.execute
        expect(result).to include('Cost Summary')
        expect(result).to include('$0.1234')
        expect(result).to include('$0.5678')
        expect(result).to include('$1.9012')
        expect(result).to include('Workers:    3')
      end
    end

    context 'with top action' do
      let(:workers_body) do
        '{"data":[{"worker_id":"w-1"},{"worker_id":"w-2"}]}'
      end
      let(:value_body) { '{"data":{"total_cost_usd":0.42}}' }

      before do
        workers_response = instance_double(Net::HTTPResponse, body: workers_body)
        value_response = instance_double(Net::HTTPResponse, body: value_body)
        allow(stub_http).to receive(:get).and_return(workers_response, value_response, value_response)
      end

      it 'returns top cost consumers' do
        result = tool.execute(action: 'top', limit: 5)
        expect(result).to include('Top')
        expect(result).to include('w-1')
      end
    end

    context 'with worker action' do
      let(:value_body) do
        '{"data":{"total_cost_usd":1.23,"total_tokens":5000,"requests":42}}'
      end

      before do
        response = instance_double(Net::HTTPResponse, body: value_body)
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns worker cost details' do
        result = tool.execute(action: 'worker', worker_id: 'w-1')
        expect(result).to include('Worker: w-1')
        expect(result).to include('total_cost_usd')
      end
    end

    context 'with worker action and missing worker_id' do
      it 'returns error message' do
        result = tool.execute(action: 'worker')
        expect(result).to include('worker_id is required')
      end
    end

    context 'with no workers for top action' do
      before do
        response = instance_double(Net::HTTPResponse, body: '{"data":[]}')
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns no workers message' do
        result = tool.execute(action: 'top')
        expect(result).to eq('No workers found.')
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

    context 'when API returns error' do
      before do
        response = instance_double(Net::HTTPResponse, body: '{"error":"internal"}')
        allow(stub_http).to receive(:get).and_return(response)
      end

      it 'returns the error message' do
        result = tool.execute
        expect(result).to include('API error: internal')
      end
    end
  end
end
