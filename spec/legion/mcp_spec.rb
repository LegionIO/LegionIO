# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP do
  before do
    described_class.reset!
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.server' do
    it 'returns a memoized MCP::Server' do
      s1 = described_class.server
      s2 = described_class.server
      expect(s1).to be(s2)
    end
  end

  describe '.server_for' do
    it 'returns error hash for invalid token' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return([])
      result = described_class.server_for(token: 'bad-key')
      expect(result).to eq({ error: 'invalid_api_key' })
    end

    it 'returns error hash for nil token' do
      result = described_class.server_for(token: nil)
      expect(result).to eq({ error: 'missing_token' })
    end

    it 'returns an MCP::Server for valid token' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return(['good-key'])
      result = described_class.server_for(token: 'good-key')
      expect(result).to be_a(::MCP::Server)
    end
  end

  describe '.reset!' do
    it 'clears the memoized server' do
      s1 = described_class.server
      described_class.reset!
      s2 = described_class.server
      expect(s1).not_to be(s2)
    end
  end
end
