# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/dashboard/data_fetcher'

RSpec.describe Legion::CLI::Dashboard::DataFetcher do
  let(:fetcher) { described_class.new(base_url: 'http://localhost:4567') }

  describe '#summary' do
    it 'returns hash with expected keys' do
      allow(fetcher).to receive(:fetch).and_return([])
      result = fetcher.summary
      expect(result.keys).to include(:workers, :health, :events, :fetched_at)
    end

    it 'includes fetched_at timestamp' do
      allow(fetcher).to receive(:fetch).and_return([])
      result = fetcher.summary
      expect(result[:fetched_at]).to be_a(Time)
    end
  end
end
