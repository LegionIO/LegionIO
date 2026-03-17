# frozen_string_literal: true

require 'spec_helper'
require 'legion/capacity/model'

RSpec.describe Legion::Capacity::Model do
  let(:workers) do
    [
      { worker_id: 'w1', status: 'active' },
      { worker_id: 'w2', status: 'active' },
      { worker_id: 'w3', status: 'stopped' }
    ]
  end
  let(:model) { described_class.new(workers: workers) }

  describe '#aggregate' do
    it 'counts active workers' do
      result = model.aggregate
      expect(result[:total_workers]).to eq(3)
      expect(result[:active_workers]).to eq(2)
    end

    it 'calculates throughput' do
      result = model.aggregate
      expect(result[:max_throughput_tps]).to eq(20)
      expect(result[:effective_throughput_tps]).to eq(14)
    end
  end

  describe '#forecast' do
    it 'projects growth' do
      result = model.forecast(days: 30, growth_rate: 0.5)
      expect(result[:projected_workers]).to be > model.aggregate[:active_workers]
    end

    it 'handles zero growth' do
      result = model.forecast(days: 30, growth_rate: 0.0)
      expect(result[:projected_workers]).to eq(model.aggregate[:active_workers])
    end
  end

  describe '#per_worker_stats' do
    it 'returns stats per worker' do
      stats = model.per_worker_stats
      expect(stats.size).to eq(3)
      active = stats.find { |s| s[:worker_id] == 'w1' }
      expect(active[:capacity_tps]).to eq(10)
    end

    it 'returns zero capacity for inactive workers' do
      stats = model.per_worker_stats
      stopped = stats.find { |s| s[:worker_id] == 'w3' }
      expect(stopped[:capacity_tps]).to eq(0)
    end
  end
end
