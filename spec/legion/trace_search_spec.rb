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
end
