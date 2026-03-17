# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/api/token'

RSpec.describe 'POST /api/auth/worker-token' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:valid_body) do
    { grant_type: 'client_credentials', entra_token: 'entra-jwt' }
  end

  let(:mock_worker) do
    double('worker', worker_id: 'wkr-uuid-1', owner_msid: 'owner@uhg.com',
                     lifecycle_state: 'active', entra_app_id: 'app-123')
  end

  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Settings).to receive(:[]).with(:identity).and_return({ entra: { tenant_id: 'tenant-1' } })
    stub_const('Legion::Data::Model::DigitalWorker', double('DW'))
  end

  context 'with valid Entra token' do
    before do
      allow(Legion::Crypt::JWT).to receive(:verify_with_jwks).and_return({ appid: 'app-123' })
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(entra_app_id: 'app-123').and_return(mock_worker)
      allow(Legion::API::Token).to receive(:issue_worker_token).and_return('legion-jwt-456')
    end

    it 'returns a Legion worker JWT' do
      post '/api/auth/worker-token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      body = Legion::JSON.load(last_response.body)
      expect(body[:data][:access_token]).to eq('legion-jwt-456')
      expect(body[:data][:scope]).to eq('worker')
      expect(body[:data][:worker_id]).to eq('wkr-uuid-1')
    end

    it 'issues token with correct worker_id' do
      expect(Legion::API::Token).to receive(:issue_worker_token).with(
        hash_including(worker_id: 'wkr-uuid-1', owner_msid: 'owner@uhg.com')
      ).and_return('legion-jwt-456')
      post '/api/auth/worker-token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
    end
  end

  context 'with invalid grant_type' do
    it 'returns 400' do
      body = valid_body.merge(grant_type: 'authorization_code')
      post '/api/auth/worker-token', Legion::JSON.dump(body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end
  end

  context 'with missing entra_token' do
    it 'returns 400' do
      body = valid_body.except(:entra_token)
      post '/api/auth/worker-token', Legion::JSON.dump(body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
    end
  end

  context 'with expired Entra token' do
    before do
      allow(Legion::Crypt::JWT).to receive(:verify_with_jwks)
        .and_raise(Legion::Crypt::JWT::ExpiredTokenError, 'expired')
    end

    it 'returns 401' do
      post '/api/auth/worker-token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(401)
    end
  end

  context 'when worker not found' do
    before do
      allow(Legion::Crypt::JWT).to receive(:verify_with_jwks).and_return({ appid: 'unknown-app' })
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).and_return(nil)
    end

    it 'returns 404' do
      post '/api/auth/worker-token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(404)
    end
  end

  context 'when worker not active' do
    before do
      paused_worker = double('worker', worker_id: 'wkr-2', lifecycle_state: 'paused',
                                       owner_msid: 'o@uhg.com', entra_app_id: 'app-x')
      allow(Legion::Crypt::JWT).to receive(:verify_with_jwks).and_return({ appid: 'app-x' })
      allow(Legion::Data::Model::DigitalWorker).to receive(:first).and_return(paused_worker)
    end

    it 'returns 403' do
      post '/api/auth/worker-token', Legion::JSON.dump(valid_body), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(403)
    end
  end
end
