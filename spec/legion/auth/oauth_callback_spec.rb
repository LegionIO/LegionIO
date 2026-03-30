# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/oauth_callback'

RSpec.describe Legion::Auth::OauthCallback do
  describe '#initialize' do
    it 'allocates a random port' do
      cb = described_class.new
      expect(cb.port).to be > 0
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
      result = nil

      thread = Thread.new do
        result = cb.wait_for_callback
      end

      # Simulate browser redirect
      sleep 0.05
      s = TCPSocket.new('127.0.0.1', cb.port)
      s.write "GET /callback?code=auth-code-123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
      begin
        s.close
      rescue Errno::ECONNRESET, Errno::EPIPE
        nil # server may close first
      end

      thread.join(5)
      expect(result[:code]).to eq('auth-code-123')
      expect(result[:state]).to eq('xyz')
    end

    it 'raises Timeout::Error when no callback arrives' do
      cb = described_class.new(timeout: 0.1)
      expect { cb.wait_for_callback }.to raise_error(Timeout::Error)
    end
  end
end
