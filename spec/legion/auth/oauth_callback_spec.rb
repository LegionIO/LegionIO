# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/oauth_callback'

RSpec.describe Legion::Auth::OauthCallback do
  let(:server) do
    instance_double(
      TCPServer,
      addr:  ['AF_INET', 42_424, '127.0.0.1', '127.0.0.1'],
      close: nil
    )
  end

  before do
    allow(TCPServer).to receive(:new).with('127.0.0.1', 0).and_return(server)
  end

  describe '#initialize' do
    it 'allocates a random port' do
      cb = described_class.new
      expect(cb.port).to eq(42_424)
      cb.close
    end

    it 'sets redirect_uri with the allocated port' do
      cb = described_class.new
      expect(cb.redirect_uri).to start_with('http://127.0.0.1:')
      expect(cb.redirect_uri).to end_with('/callback')
      cb.close
    end
  end

  describe '#wait_for_callback' do
    it 'receives the authorization code from the callback' do
      cb = described_class.new
      client = instance_double(
        TCPSocket,
        gets:  "GET /callback?code=auth-code-123&state=xyz HTTP/1.1\r\n",
        close: nil
      )
      allow(client).to receive(:puts)
      allow(server).to receive(:accept).and_return(client)

      result = cb.wait_for_callback

      expect(result[:code]).to eq('auth-code-123')
      expect(result[:state]).to eq('xyz')
    end

    it 'raises Timeout::Error when no callback arrives' do
      cb = described_class.new(timeout: 0.1)
      allow(server).to receive(:accept) { sleep 0.2 }

      expect { cb.wait_for_callback }.to raise_error(Timeout::Error)
    end
  end
end
