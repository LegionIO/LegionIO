# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/token_manager'

RSpec.describe Legion::Auth::TokenManager do
  let(:manager) { described_class.new(provider: :microsoft) }
  let(:mock_secret) { {} }

  before { allow(manager).to receive(:secret).and_return(mock_secret) }

  describe '#token_valid?' do
    it 'returns false when no token stored' do
      expect(manager.token_valid?).to be false
    end

    it 'returns true when token is fresh' do
      mock_secret[:microsoft_token_expires_at] = (Time.now + 3600).iso8601
      mock_secret[:microsoft_access_token] = 'valid-token'
      expect(manager.token_valid?).to be true
    end

    it 'returns false when token is expiring soon (75% threshold)' do
      mock_secret[:microsoft_token_expires_at] = (Time.now + 60).iso8601
      mock_secret[:microsoft_access_token] = 'valid-token'
      mock_secret[:microsoft_token_ttl] = 3600
      expect(manager.token_valid?).to be false
    end
  end

  describe '#store_tokens' do
    it 'stores access and refresh tokens' do
      manager.store_tokens(
        access_token:  'at-123',
        refresh_token: 'rt-456',
        expires_in:    3600,
        scope:         'Calendars.Read'
      )
      expect(mock_secret[:microsoft_access_token]).to eq('at-123')
      expect(mock_secret[:microsoft_refresh_token]).to eq('rt-456')
    end
  end

  describe '#ensure_valid_token' do
    it 'returns cached token when still valid' do
      mock_secret[:microsoft_access_token] = 'cached'
      mock_secret[:microsoft_token_expires_at] = (Time.now + 3600).iso8601
      expect(manager.ensure_valid_token).to eq('cached')
    end
  end
end
