# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/system_status'

RSpec.describe Legion::CLI::Chat::Tools::SystemStatus do
  subject(:tool) { described_class.new }

  let(:mock_http) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    it 'returns formatted status with health and readiness' do
      health_response = instance_double(Net::HTTPOK)
      allow(health_response).to receive(:body).and_return(
        JSON.generate({
                        status:         'ok',
                        version:        '1.4.150',
                        node:           'dev-laptop',
                        uptime_seconds: 3661,
                        pid:            12_345
                      })
      )

      ready_response = instance_double(Net::HTTPOK)
      allow(ready_response).to receive(:body).and_return(
        JSON.generate({
                        components:      {
                          settings:   true,
                          crypt:      true,
                          transport:  true,
                          cache:      false,
                          data:       true,
                          gaia:       false,
                          extensions: true,
                          api:        true
                        },
                        extension_count: 12
                      })
      )

      call_count = 0
      allow(mock_http).to receive(:get) do |_uri|
        call_count += 1
        call_count == 1 ? health_response : ready_response
      end

      result = tool.execute
      expect(result).to include('Legion System Status')
      expect(result).to include('Status: ok')
      expect(result).to include('Version: 1.4.150')
      expect(result).to include('Node: dev-laptop')
      expect(result).to include('1h 1m')
      expect(result).to include('PID: 12345')
      expect(result).to include('settings: ready')
      expect(result).to include('cache: not ready')
      expect(result).to include('6/8 ready')
      expect(result).to include('Extensions: 12')
    end

    it 'handles daemon not running' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      result = tool.execute
      expect(result).to include('daemon not running')
    end

    it 'handles both endpoints failing gracefully' do
      allow(mock_http).to receive(:get).and_raise(StandardError.new('timeout'))

      result = tool.execute
      expect(result).to include('Health endpoint: unreachable')
    end

    it 'formats uptime with days' do
      health_response = instance_double(Net::HTTPOK)
      allow(health_response).to receive(:body).and_return(
        JSON.generate({ status: 'ok', uptime_seconds: 90_061 })
      )
      ready_response = instance_double(Net::HTTPOK)
      allow(ready_response).to receive(:body).and_return(JSON.generate({ components: {} }))

      call_count = 0
      allow(mock_http).to receive(:get) do |_uri|
        call_count += 1
        call_count == 1 ? health_response : ready_response
      end

      result = tool.execute
      expect(result).to include('1d 1h 1m')
    end

    it 'formats short uptime in seconds' do
      health_response = instance_double(Net::HTTPOK)
      allow(health_response).to receive(:body).and_return(
        JSON.generate({ status: 'ok', uptime_seconds: 45 })
      )
      ready_response = instance_double(Net::HTTPOK)
      allow(ready_response).to receive(:body).and_return(JSON.generate({ components: {} }))

      call_count = 0
      allow(mock_http).to receive(:get) do |_uri|
        call_count += 1
        call_count == 1 ? health_response : ready_response
      end

      result = tool.execute
      expect(result).to include('45s')
    end

    it 'handles empty components' do
      health_response = instance_double(Net::HTTPOK)
      allow(health_response).to receive(:body).and_return(
        JSON.generate({ status: 'ok' })
      )
      ready_response = instance_double(Net::HTTPOK)
      allow(ready_response).to receive(:body).and_return(JSON.generate({ components: {} }))

      call_count = 0
      allow(mock_http).to receive(:get) do |_uri|
        call_count += 1
        call_count == 1 ? health_response : ready_response
      end

      result = tool.execute
      expect(result).to include('Status: ok')
      expect(result).not_to include('Components:')
    end
  end
end
