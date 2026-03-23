# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/ingest_knowledge'

RSpec.describe Legion::CLI::Chat::Tools::IngestKnowledge do
  let(:tool) { described_class.new }

  let(:success_response) do
    response = instance_double(Net::HTTPSuccess, body: JSON.dump({ data: { id: 42, status: 'created' } }))
    allow(response).to receive(:is_a?).with(anything).and_return(false)
    response
  end

  before do
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(success_response)
  end

  describe '#execute' do
    it 'returns success message with id' do
      result = tool.execute(content: 'Ruby uses GIL for thread safety')
      expect(result).to include('Saved to Apollo')
      expect(result).to include('id: 42')
    end

    it 'defaults content_type to observation' do
      result = tool.execute(content: 'test')
      expect(result).to include('type: observation')
    end

    it 'accepts valid content types' do
      result = tool.execute(content: 'test', content_type: 'fact')
      expect(result).to include('type: fact')
    end

    it 'rejects invalid content types and falls back to observation' do
      result = tool.execute(content: 'test', content_type: 'garbage')
      expect(result).to include('type: observation')
    end

    it 'parses comma-separated tags' do
      result = tool.execute(content: 'test', tags: 'ruby, performance, gc')
      expect(result).to include('ruby')
      expect(result).to include('performance')
    end

    it 'handles empty tags gracefully' do
      result = tool.execute(content: 'test', tags: '')
      expect(result).to include('Saved to Apollo')
    end

    it 'returns error when API returns error' do
      error_response = instance_double(Net::HTTPSuccess,
                                       body: JSON.dump({ data: { error: 'validation failed' } }))
      allow(error_response).to receive(:is_a?).with(anything).and_return(false)
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(error_response)

      result = tool.execute(content: 'test')
      expect(result).to include('Failed to ingest')
    end

    it 'returns unavailable message when daemon is down' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      result = tool.execute(content: 'test')
      expect(result).to include('Apollo unavailable')
    end

    it 'returns error message on unexpected failure' do
      allow(Net::HTTP).to receive(:new).and_raise(StandardError, 'network error')
      result = tool.execute(content: 'test')
      expect(result).to include('Error saving to knowledge graph')
      expect(result).to include('network error')
    end
  end
end
