# frozen_string_literal: true

require 'spec_helper'
require 'sinatra/base'
require 'legion/api/auth_teams'

RSpec.describe Legion::API::Routes::AuthTeams::TeamsTokenHelper do
  subject(:helper) { Object.new.extend(described_class) }

  let(:token_manager) do
    class_double('Legion::Extensions::Identity::Entra::Helpers::TokenManager', save_token: true)
  end

  let(:token_body) do
    { access_token: 'at', refresh_token: 'rt', expires_in: 3600 }
  end

  before do
    stub_const('Legion::Extensions::Identity::Entra::Helpers::TokenManager', token_manager)
    allow(helper).to receive(:require).and_return(true)
  end

  describe '#store_teams_token' do
    it 'persists the delegated token via the Entra TokenManager' do
      helper.store_teams_token(token_body, 'OnlineMeetings.Read',
                               tenant_id: 'tid', client_id: 'cid')

      expect(token_manager).to have_received(:save_token).with(
        :delegated,
        access_token:  'at',
        refresh_token: 'rt',
        expires_in:    3600,
        scopes:        'OnlineMeetings.Read',
        tenant_id:     'tid',
        client_id:     'cid'
      )
    end

    it 'forwards tenant_id and client_id so the stored token can be refreshed' do
      helper.store_teams_token(token_body, 'scope', tenant_id: 'tid', client_id: 'cid')

      expect(token_manager).to have_received(:save_token)
        .with(:delegated, hash_including(tenant_id: 'tid', client_id: 'cid'))
    end

    it 'does not raise when the token store fails and returns false' do
      allow(token_manager).to receive(:save_token).and_raise(StandardError, 'vault down')

      expect(helper.store_teams_token(token_body, 'scope', tenant_id: 't', client_id: 'c')).to be(false)
    end

    it 'returns true and resets the cached Entra delegated client on success' do
      client = class_double('Legion::Extensions::Identity::Entra::Client', reset!: true)
      stub_const('Legion::Extensions::Identity::Entra::Client', client)

      expect(helper.store_teams_token(token_body, 'scope', tenant_id: 't', client_id: 'c')).to be(true)
      expect(client).to have_received(:reset!).with(pattern: :delegated)
    end
  end
end
