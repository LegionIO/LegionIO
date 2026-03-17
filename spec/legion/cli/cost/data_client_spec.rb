# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/cost/data_client'

RSpec.describe Legion::CLI::CostData::Client do
  let(:client) { described_class.new(base_url: 'http://localhost:4567') }

  describe '#summary' do
    it 'returns default when api unavailable' do
      allow(client).to receive(:fetch).and_return(nil)
      result = client.summary
      expect(result).to have_key(:today)
      expect(result[:today]).to eq(0.0)
    end

    it 'returns api data when available' do
      data = { today: 5.25, week: 30.0, month: 120.0, workers: 3 }
      allow(client).to receive(:fetch).and_return(data)
      result = client.summary
      expect(result[:today]).to eq(5.25)
    end
  end

  describe '#worker_cost' do
    it 'returns empty hash when api unavailable' do
      allow(client).to receive(:fetch).and_return(nil)
      expect(client.worker_cost('w1')).to eq({})
    end
  end

  describe '#top_consumers' do
    it 'returns sorted list' do
      allow(client).to receive(:fetch).with('/api/workers').and_return([
                                                                         { worker_id: 'w1' },
                                                                         { worker_id: 'w2' }
                                                                       ])
      allow(client).to receive(:fetch).with('/api/workers/w1/value').and_return({ total_cost_usd: 10 })
      allow(client).to receive(:fetch).with('/api/workers/w2/value').and_return({ total_cost_usd: 20 })

      result = client.top_consumers(limit: 2)
      expect(result.first[:worker_id]).to eq('w2')
    end

    it 'handles empty worker list' do
      allow(client).to receive(:fetch).with('/api/workers').and_return([])
      expect(client.top_consumers).to eq([])
    end
  end
end
