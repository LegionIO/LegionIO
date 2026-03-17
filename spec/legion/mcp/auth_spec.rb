# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/auth'

RSpec.describe Legion::MCP::Auth do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  describe '.authenticate' do
    it 'returns error for nil token' do
      result = described_class.authenticate(nil)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to eq('missing_token')
    end

    it 'validates API key from allowed list' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return(['valid-key'])
      result = described_class.authenticate('valid-key')
      expect(result[:authenticated]).to be true
      expect(result[:identity][:user_id]).to eq('api_key')
    end

    it 'rejects invalid API key' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return(['valid-key'])
      result = described_class.authenticate('bad-key')
      expect(result[:authenticated]).to be false
      expect(result[:error]).to eq('invalid_api_key')
    end

    context 'with JWT-shaped token' do
      let(:jwt_token) { 'header.payload.signature' }

      it 'returns crypt_unavailable when Legion::Crypt::JWT is not defined' do
        hide_const('Legion::Crypt::JWT') if defined?(Legion::Crypt::JWT)
        result = described_class.authenticate(jwt_token)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('crypt_unavailable')
      end

      it 'returns error for invalid JWT when Crypt is available' do
        if defined?(Legion::Crypt::JWT)
          result = described_class.authenticate(jwt_token)
          expect(result[:authenticated]).to be false
          expect(result[:error]).to be_a(String)
        end
      end
    end
  end

  describe '.auth_enabled?' do
    it 'returns false when not configured' do
      expect(described_class.auth_enabled?).to be false
    end

    it 'returns true when enabled in settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :enabled).and_return(true)
      expect(described_class.auth_enabled?).to be true
    end
  end

  describe '.jwt_token?' do
    it 'identifies JWT tokens by dot count' do
      expect(described_class.jwt_token?('a.b.c')).to be true
      expect(described_class.jwt_token?('plain-key')).to be false
    end
  end
end
