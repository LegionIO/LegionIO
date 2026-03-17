# frozen_string_literal: true

require_relative 'api_spec_helper'
require 'legion/digital_worker/lifecycle'

RSpec.describe 'Workers API lifecycle' do
  include Rack::Test::Methods

  def app
    Legion::API
  end

  before(:all) { ApiSpecSetup.configure_settings }

  let(:worker_id) { 'w-abc-123' }
  let(:worker) do
    double('worker',
           worker_id:       worker_id,
           lifecycle_state: 'active',
           values:          { worker_id: worker_id, lifecycle_state: 'paused' })
  end

  def patch_lifecycle(id, body)
    patch "/api/workers/#{id}/lifecycle",
          Legion::JSON.dump(body),
          'CONTENT_TYPE' => 'application/json'
  end

  describe 'PATCH /api/workers/:id/lifecycle' do
    context 'when data is not connected' do
      it 'returns 503' do
        patch_lifecycle(worker_id, { state: 'paused' })
        expect(last_response.status).to eq(503)
      end
    end

    context 'when data is connected' do
      let(:worker_model) { double('Legion::Data::Model::DigitalWorker') }

      before do
        stub_const('Legion::Data::Model::DigitalWorker', worker_model)
        Legion::Settings.loader.settings[:data] = { connected: true }
        allow(worker_model).to receive(:first).with(worker_id: worker_id).and_return(worker)
      end

      after do
        Legion::Settings.loader.settings[:data] = { connected: false }
      end

      context 'when state is missing' do
        it 'returns 422 with missing_field error' do
          patch_lifecycle(worker_id, { reason: 'test' })
          expect(last_response.status).to eq(422)
          body = Legion::JSON.load(last_response.body)
          expect(body[:error][:code]).to eq('missing_field')
        end
      end

      context 'when transition is invalid' do
        it 'returns 422 with invalid_transition error' do
          allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
            .and_raise(Legion::DigitalWorker::Lifecycle::InvalidTransition,
                       'cannot transition from active to bootstrap')

          patch_lifecycle(worker_id, { state: 'bootstrap' })
          expect(last_response.status).to eq(422)
          body = Legion::JSON.load(last_response.body)
          expect(body[:error][:code]).to eq('invalid_transition')
        end
      end

      context 'when GovernanceRequired is raised (no governance_override)' do
        it 'returns 403 with governance_required error code' do
          allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
            .and_raise(Legion::DigitalWorker::Lifecycle::GovernanceRequired,
                       'active -> terminated requires council_approval')

          patch_lifecycle(worker_id, { state: 'terminated' })
          expect(last_response.status).to eq(403)
          body = Legion::JSON.load(last_response.body)
          expect(body[:error][:code]).to eq('governance_required')
          expect(body[:error][:message]).to match(/council_approval/)
        end
      end

      context 'when AuthorityRequired is raised (no authority_verified)' do
        it 'returns 403 with authority_required error code' do
          allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
            .and_raise(Legion::DigitalWorker::Lifecycle::AuthorityRequired,
                       'active -> paused requires owner_or_manager')

          patch_lifecycle(worker_id, { state: 'paused' })
          expect(last_response.status).to eq(403)
          body = Legion::JSON.load(last_response.body)
          expect(body[:error][:code]).to eq('authority_required')
          expect(body[:error][:message]).to match(/owner_or_manager/)
        end
      end

      context 'when governance_override is provided in the request body' do
        it 'passes governance_override: true to transition!' do
          expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
            worker,
            to_state:            'terminated',
            by:                  'api',
            reason:              nil,
            governance_override: true,
            authority_verified:  false
          ).and_return(worker)

          patch_lifecycle(worker_id, { state: 'terminated', governance_override: true })
          expect(last_response.status).to eq(200)
        end
      end

      context 'when authority_verified is provided in the request body' do
        it 'passes authority_verified: true to transition!' do
          expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
            worker,
            to_state:            'paused',
            by:                  'api',
            reason:              nil,
            governance_override: false,
            authority_verified:  true
          ).and_return(worker)

          patch_lifecycle(worker_id, { state: 'paused', authority_verified: true })
          expect(last_response.status).to eq(200)
        end
      end

      context 'when worker is not found' do
        it 'returns 404' do
          allow(worker_model).to receive(:first).with(worker_id: 'unknown').and_return(nil)

          patch_lifecycle('unknown', { state: 'paused' })
          expect(last_response.status).to eq(404)
        end
      end
    end
  end
end
