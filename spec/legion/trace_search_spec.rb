# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
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

  describe '.search' do
    it 'returns empty results with error when LLM unavailable' do
      result = described_class.search('test query')
      expect(result[:error]).to eq('no filter generated')
      expect(result[:results]).to eq([])
    end

    context 'when LLM generates a filter' do
      before do
        allow(described_class).to receive(:generate_filter).and_return({ where: { status: 'failure' } })
      end

      it 'returns data unavailable error when data is not connected' do
        result = described_class.search('failed tasks')
        expect(result[:error]).to include('data unavailable')
      end
    end
  end

  describe 'ALLOWED_COLUMNS' do
    it 'includes expected columns' do
      expect(described_class::ALLOWED_COLUMNS).to include('worker_id', 'status', 'cost_usd')
    end

    it 'does not include dangerous columns' do
      expect(described_class::ALLOWED_COLUMNS).not_to include('password', 'token', 'secret')
    end
  end

  describe 'FILTER_SCHEMA' do
    it 'defines expected properties' do
      props = described_class::FILTER_SCHEMA[:properties]
      expect(props).to have_key(:where)
      expect(props).to have_key(:order)
      expect(props).to have_key(:limit)
      expect(props).to have_key(:date_from)
      expect(props).to have_key(:date_to)
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

    it 'parses datetime strings' do
      result = described_class.safe_parse_time('2026-03-23T14:30:00Z')
      expect(result).to be_a(Time)
      expect(result.hour).to eq(14)
    end

    it 'returns nil for unparseable strings' do
      expect(described_class.safe_parse_time('not-a-date')).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.safe_parse_time('')).to be_nil
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

    it 'applies ascending order for allowed column' do
      allow(mock_dataset).to receive(:order).and_return(mock_dataset)
      result = described_class.apply_ordering(mock_dataset, { order: 'cost_usd' })
      expect(mock_dataset).to have_received(:order).with(:cost_usd)
      expect(result).to eq(mock_dataset)
    end

    it 'applies descending order when prefixed with dash' do
      allow(mock_dataset).to receive(:order).and_return(mock_dataset)
      result = described_class.apply_ordering(mock_dataset, { order: '-cost_usd' })
      expect(mock_dataset).to have_received(:order) do |arg|
        expect(arg).to be_a(Sequel::SQL::OrderedExpression)
      end
      expect(result).to eq(mock_dataset)
    end
  end

  describe '.apply_date_filters' do
    let(:mock_dataset) { double('Dataset') }

    it 'returns dataset unchanged when no dates provided' do
      expect(described_class.apply_date_filters(mock_dataset, {})).to eq(mock_dataset)
    end

    it 'applies date_from filter' do
      filtered = double('FilteredDataset')
      allow(mock_dataset).to receive(:where).and_return(filtered)
      result = described_class.apply_date_filters(mock_dataset, { date_from: '2026-03-01' })
      expect(result).to eq(filtered)
    end

    it 'applies date_to filter' do
      filtered = double('FilteredDataset')
      allow(mock_dataset).to receive(:where).and_return(filtered)
      result = described_class.apply_date_filters(mock_dataset, { date_to: '2026-03-31' })
      expect(result).to eq(filtered)
    end

    it 'skips invalid date strings' do
      result = described_class.apply_date_filters(mock_dataset, { date_from: 'invalid' })
      expect(result).to eq(mock_dataset)
    end
  end
end
