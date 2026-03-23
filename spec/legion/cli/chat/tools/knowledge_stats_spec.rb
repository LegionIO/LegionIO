# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/knowledge_stats'

RSpec.describe Legion::CLI::Chat::Tools::KnowledgeStats do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'returns formatted stats' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({
                        data: {
                          total_entries:   42,
                          recent_24h:      8,
                          avg_confidence:  0.782,
                          by_status:       { confirmed: 30, pending: 12 },
                          by_content_type: { fact: 20, observation: 15, concept: 7 }
                        }
                      })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Total entries: 42')
      expect(result).to include('Recent (24h): 8')
      expect(result).to include('Avg confidence: 0.782')
      expect(result).to include('confirmed: 30')
      expect(result).to include('fact: 20')
      expect(result).to include('By Status')
      expect(result).to include('By Content Type')
    end

    it 'handles empty breakdowns' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { total_entries: 0, recent_24h: 0, avg_confidence: 0.0 } })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Total entries: 0')
      expect(result).not_to include('By Status')
    end

    it 'returns error from API' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { error: 'apollo_entries table not available' } })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Apollo error: apollo_entries table not available')
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      result = tool.execute
      expect(result).to include('Apollo unavailable')
    end

    it 'handles missing fields with defaults' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: {} })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Total entries: 0')
      expect(result).to include('Avg confidence: 0.0')
    end
  end
end
