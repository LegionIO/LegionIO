# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/relate_knowledge'

RSpec.describe Legion::CLI::Chat::Tools::RelateKnowledge do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'returns formatted related entries' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({
                        data: {
                          entries: [
                            { content: 'AMQP uses RabbitMQ', relation_type: 'supports', confidence: 0.9 },
                            { content: 'Messaging is async', relation_type: 'related', confidence: 0.7 }
                          ]
                        }
                      })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(entry_id: 42)
      expect(result).to include('Related entries for #42')
      expect(result).to include('[supports]')
      expect(result).to include('AMQP uses RabbitMQ')
      expect(result).to include('(conf: 0.9)')
    end

    it 'returns message when no related entries found' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: { entries: [] } }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(entry_id: 99)
      expect(result).to include('No related entries found')
    end

    it 'returns error from API' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: { error: 'not found' } }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(entry_id: 1)
      expect(result).to include('Apollo error: not found')
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      result = tool.execute(entry_id: 1)
      expect(result).to include('Apollo unavailable')
    end

    it 'clamps depth to 1-3' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: { entries: [] } }))
      expect(mock_http).to receive(:get) do |uri|
        expect(uri).to include('depth=3')
        response
      end

      tool.execute(entry_id: 1, depth: 10)
    end

    it 'passes relation_types as query param' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ data: { entries: [] } }))
      expect(mock_http).to receive(:get) do |uri|
        expect(uri).to include('relation_types=supports,contradicts')
        response
      end

      tool.execute(entry_id: 1, relation_types: 'supports,contradicts')
    end

    it 'includes depth in output header' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { entries: [{ content: 'test' }] } })
      )
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute(entry_id: 5, depth: 3)
      expect(result).to include('depth: 3')
    end
  end
end
