# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'Governance API' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  before do
    allow_any_instance_of(Legion::API).to receive(:require_data!).and_return(true)
  end

  describe 'GET /api/governance/approvals' do
    it 'returns a list of approvals' do
      allow_any_instance_of(Legion::API).to receive(:run_governance_runner).and_return(
        { success: true, approvals: [], count: 0 }
      )

      get '/api/governance/approvals'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /api/governance/approvals' do
    it 'creates a new approval' do
      allow_any_instance_of(Legion::API).to receive(:run_governance_runner).and_return(
        { success: true, approval_id: 1, status: 'pending' }
      )

      post '/api/governance/approvals',
           Legion::JSON.dump({ approval_type: 'worker_deploy', payload: { name: 'test-worker' },
                               requester_id: 'user-1' }),
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(201)
    end
  end

  describe 'PUT /api/governance/approvals/:id/approve' do
    it 'approves an approval' do
      allow_any_instance_of(Legion::API).to receive(:run_governance_runner).and_return(
        { success: true, approval_id: 1, status: 'approved' }
      )

      put '/api/governance/approvals/1/approve',
          Legion::JSON.dump({ reviewer_id: 'reviewer-1' }),
          { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end
  end

  describe 'PUT /api/governance/approvals/:id/reject' do
    it 'rejects an approval' do
      allow_any_instance_of(Legion::API).to receive(:run_governance_runner).and_return(
        { success: true, approval_id: 1, status: 'rejected' }
      )

      put '/api/governance/approvals/1/reject',
          Legion::JSON.dump({ reviewer_id: 'reviewer-1' }),
          { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
    end
  end
end
