# frozen_string_literal: true

require 'spec_helper'
require 'legion/trace_search'

RSpec.describe Legion::TraceSearch do
  describe '.generate_filter' do
    it 'returns nil when LLM unavailable' do
      expect(described_class.generate_filter('test')).to be_nil
    end
  end

  describe '.execute_filter' do
    it 'returns error when data unavailable' do
      result = described_class.execute_filter({ where: { status: 'failure' } }, 10)
      expect(result[:error]).to include('data unavailable')
    end
  end

  describe 'ALLOWED_COLUMNS' do
    it 'includes expected columns' do
      expect(described_class::ALLOWED_COLUMNS).to include('worker_id', 'status', 'cost_usd')
    end
  end

  describe 'FILTER_SCHEMA' do
    it 'defines expected properties' do
      props = described_class::FILTER_SCHEMA[:properties]
      expect(props).to have_key(:where)
      expect(props).to have_key(:order)
      expect(props).to have_key(:limit)
    end
  end

  describe '.safe_parse_time' do
    it 'returns Time objects unchanged' do
      now = Time.now.utc
      expect(described_class.safe_parse_time(now)).to eq(now)
    end

    it 'parses ISO 8601 date strings' do
      result = described_class.safe_parse_time('2026-03-23')
      expect(result).to be_a(Time)
      expect(result.year).to eq(2026)
      expect(result.month).to eq(3)
      expect(result.day).to eq(23)
    end

    it 'returns nil for unparseable strings' do
      expect(described_class.safe_parse_time('not-a-date')).to be_nil
    end
  end

  describe '.apply_ordering' do
    let(:mock_dataset) { double('Dataset') }

    it 'returns dataset unchanged when order is not a string' do
      expect(described_class.apply_ordering(mock_dataset, { order: nil })).to eq(mock_dataset)
    end

    it 'returns dataset unchanged for disallowed columns' do
      expect(described_class.apply_ordering(mock_dataset, { order: 'password' })).to eq(mock_dataset)
    end
  end
end
