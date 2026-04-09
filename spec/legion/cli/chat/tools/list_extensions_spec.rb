# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/list_extensions'

RSpec.describe Legion::CLI::Chat::Tools::ListExtensions do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'listing all extensions' do
      it 'returns formatted extension list' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(
          JSON.generate({
                          data: [
                            { name: 'lex-node', state: 'running' },
                            { name: 'lex-scheduler', state: 'running' },
                            { name: 'lex-detect', state: 'stopped' }
                          ]
                        })
        )
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute
        expect(result).to include('Loaded Extensions (3)')
        expect(result).to include('lex-node (running)')
        expect(result).to include('lex-detect (stopped)')
      end

      it 'returns message when no extensions found' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
        allow(mock_http).to receive(:get).and_return(response)

        result = tool.execute
        expect(result).to include('No extensions found')
      end

      it 'passes state filter' do
        response = instance_double(Net::HTTPOK)
        allow(response).to receive(:body).and_return(JSON.generate({ data: [] }))
        expect(mock_http).to receive(:get) do |uri|
          expect(uri).to include('state=running')
          response
        end

        tool.execute(state: 'running')
      end
    end

    context 'extension detail' do
      it 'returns extension detail with runners' do
        ext_response = instance_double(Net::HTTPOK)
        allow(ext_response).to receive(:body).and_return(
          JSON.generate({
                          data: { name: 'lex-node', state: 'running', version: '1.0.0' }
                        })
        )

        runners_response = instance_double(Net::HTTPOK)
        allow(runners_response).to receive(:body).and_return(
          JSON.generate({
                          data: [
                            { name: 'node_info', runner_class: 'Legion::Extensions::Node::Runners::Info' }
                          ]
                        })
        )

        call_count = 0
        allow(mock_http).to receive(:get) do |_uri|
          call_count += 1
          call_count == 1 ? ext_response : runners_response
        end

        result = tool.execute(extension_name: 'lex-node')
        expect(result).to include('Extension: lex-node')
        expect(result).to include('State: running')
        expect(result).to include('Runners (1)')
        expect(result).to include('node_info')
      end

      it 'handles extension with no runners' do
        ext_response = instance_double(Net::HTTPOK)
        allow(ext_response).to receive(:body).and_return(
          JSON.generate({ data: { name: 'lex-empty', state: 'running' } })
        )

        runners_response = instance_double(Net::HTTPOK)
        allow(runners_response).to receive(:body).and_return(JSON.generate({ data: [] }))

        call_count = 0
        allow(mock_http).to receive(:get) do |_uri|
          call_count += 1
          call_count == 1 ? ext_response : runners_response
        end

        result = tool.execute(extension_name: 'lex-empty')
        expect(result).to include('No runners registered')
      end
    end

    it 'handles connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      result = tool.execute
      expect(result).to include('daemon not running')
    end

    it 'handles API error response' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(JSON.generate({ error: 'data unavailable' }))
      allow(mock_http).to receive(:get).and_return(response)

      result = tool.execute
      expect(result).to include('API error: data unavailable')
    end
  end
end
