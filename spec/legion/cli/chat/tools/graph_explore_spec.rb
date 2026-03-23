# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/graph_explore'

RSpec.describe Legion::CLI::Chat::Tools::GraphExplore do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  let(:graph_body) do
    JSON.generate({
                    data: {
                      domains:          { 'general' => 15, 'claims_optimization' => 8 },
                      agents:           { 'claude-agent' => 12, 'openai-agent' => 11 },
                      relation_types:   { 'similar_to' => 10, 'contradicts' => 3 },
                      total_relations:  13,
                      confirmed:        18,
                      candidates:       3,
                      disputed_entries: 2
                    }
                  })
  end

  let(:expertise_body) do
    JSON.generate({
                    data: {
                      total_agents:  2,
                      total_domains: 1,
                      domains:       {
                        'general' => [
                          { agent_id: 'claude-agent', proficiency: 0.85, entry_count: 12 },
                          { agent_id: 'openai-agent', proficiency: 0.6, entry_count: 8 }
                        ]
                      }
                    }
                  })
  end

  let(:disputed_body) do
    JSON.generate({
                    data: {
                      entries: [
                        { id: 42, content: 'Disputed claim about caching', confidence: 0.35,
                          content_type: 'fact', tags: ['cache'], source_agent: 'claude-agent' }
                      ],
                      count:   1
                    }
                  })
  end

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'returns topology by default' do
      response = instance_double(Net::HTTPOK, body: graph_body)
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('Knowledge Graph Topology')
      expect(result).to include('general')
      expect(result).to include('claims_optimization')
      expect(result).to include('similar_to')
      expect(result).to include('Confirmed: 18')
    end

    it 'shows expertise map' do
      response = instance_double(Net::HTTPOK, body: expertise_body)
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(action: 'expertise')
      expect(result).to include('Expertise Map')
      expect(result).to include('claude-agent')
      expect(result).to include('85.0%')
    end

    it 'shows disputed entries' do
      response = instance_double(Net::HTTPOK, body: disputed_body)
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'disputed')
      expect(result).to include('Disputed Knowledge Entries')
      expect(result).to include('#42')
      expect(result).to include('Disputed claim about caching')
    end

    it 'handles empty disputed list' do
      response = instance_double(Net::HTTPOK, body: JSON.generate({ data: { entries: [], count: 0 } }))
      allow(mock_http).to receive(:request).and_return(response)

      result = tool.execute(action: 'disputed')
      expect(result).to eq('No disputed entries in the knowledge graph.')
    end

    it 'handles connection refused' do
      allow(mock_http).to receive(:get).and_raise(Errno::ECONNREFUSED)

      result = tool.execute
      expect(result).to eq('Apollo unavailable (daemon not running).')
    end
  end
end
