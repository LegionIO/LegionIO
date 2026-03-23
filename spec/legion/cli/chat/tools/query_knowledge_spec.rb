# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/query_knowledge'

RSpec.describe Legion::CLI::Chat::Tools::QueryKnowledge do
  let(:tool) { described_class.new }
  let(:mock_http) { instance_double(Net::HTTP) }

  let(:query_response_body) do
    JSON.generate({
                    data: {
                      entries: [
                        { content: 'Legion uses AMQP for messaging', content_type: 'fact',
                          confidence: 0.95, tags: %w[architecture transport] },
                        { content: 'Extensions are discovered via Bundler', content_type: 'fact',
                          confidence: 0.88, tags: %w[extensions] }
                      ]
                    }
                  })
  end

  let(:empty_response_body) do
    JSON.generate({ data: { entries: [] } })
  end

  let(:error_response_body) do
    JSON.generate({ data: { error: 'apollo not available' } })
  end

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'with matching results' do
      before do
        response = instance_double(Net::HTTPOK, body: query_response_body)
        allow(mock_http).to receive(:request).and_return(response)
      end

      it 'returns formatted entries' do
        result = tool.execute(query: 'how does legion communicate')
        expect(result).to include('Found 2 knowledge entries')
      end

      it 'includes content type' do
        result = tool.execute(query: 'messaging')
        expect(result).to include('[fact]')
      end

      it 'includes confidence score' do
        result = tool.execute(query: 'messaging')
        expect(result).to include('confidence: 0.95')
      end

      it 'includes content text' do
        result = tool.execute(query: 'amqp')
        expect(result).to include('Legion uses AMQP')
      end

      it 'includes tags' do
        result = tool.execute(query: 'amqp')
        expect(result).to include('architecture')
      end
    end

    context 'with no results' do
      before do
        response = instance_double(Net::HTTPOK, body: empty_response_body)
        allow(mock_http).to receive(:request).and_return(response)
      end

      it 'returns no results message' do
        result = tool.execute(query: 'nonexistent topic')
        expect(result).to include('No knowledge entries found')
      end
    end

    context 'when apollo returns error' do
      before do
        response = instance_double(Net::HTTPOK, body: error_response_body)
        allow(mock_http).to receive(:request).and_return(response)
      end

      it 'returns error message' do
        result = tool.execute(query: 'anything')
        expect(result).to include('apollo not available')
      end
    end

    context 'when connection fails' do
      before do
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      end

      it 'returns error message' do
        result = tool.execute(query: 'test')
        expect(result).to include('Error querying knowledge graph')
      end
    end

    context 'with domain filter' do
      before do
        response = instance_double(Net::HTTPOK, body: query_response_body)
        allow(mock_http).to receive(:request) do |req|
          body = JSON.parse(req.body, symbolize_names: true)
          expect(body[:domain]).to eq('architecture')
          response
        end
        allow(response).to receive(:body).and_return(query_response_body)
      end

      it 'passes domain to API' do
        tool.execute(query: 'test', domain: 'architecture')
      end
    end

    context 'with limit' do
      before do
        response = instance_double(Net::HTTPOK, body: query_response_body)
        allow(mock_http).to receive(:request) do |req|
          body = JSON.parse(req.body, symbolize_names: true)
          expect(body[:limit]).to eq(5)
          response
        end
        allow(response).to receive(:body).and_return(query_response_body)
      end

      it 'passes limit to API' do
        tool.execute(query: 'test', limit: 5)
      end
    end

    it 'clamps limit to 1..50' do
      response = instance_double(Net::HTTPOK, body: query_response_body)
      allow(mock_http).to receive(:request) do |req|
        body = JSON.parse(req.body, symbolize_names: true)
        expect(body[:limit]).to eq(50)
        response
      end

      tool.execute(query: 'test', limit: 999)
    end
  end
end
