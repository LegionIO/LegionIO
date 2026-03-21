# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

unless defined?(Legion::Data::Model::DigitalWorker)
  module Legion
    module Data
      module Model
        class DigitalWorker; end # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

require 'legion/digital_worker/lifecycle'
require 'legion/digital_worker/registration'
require 'legion/digital_worker/airb'

RSpec.describe Legion::DigitalWorker::Airb do
  let(:worker_id) { SecureRandom.uuid }
  let(:intake_id) { "airb-mock-#{worker_id[0..7]}-12345" }

  before do
    allow(Legion::Logging).to receive(:info)  if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:warn)  if defined?(Legion::Logging)
    allow(Legion::Logging).to receive(:debug) if defined?(Legion::Logging)
  end

  describe '.create_intake' do
    context 'without a live API configured (mock mode)' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:airb, :api_endpoint).and_return(nil) if defined?(Legion::Settings)
      end

      it 'returns a mock intake_id string' do
        result = described_class.create_intake(worker_id, description: 'test worker registration')
        expect(result).to be_a(String)
        expect(result).to include('airb-mock')
      end

      it 'includes the worker_id prefix in the intake_id' do
        result = described_class.create_intake(worker_id, description: 'test')
        expect(result).to include(worker_id[0..7])
      end
    end
  end

  describe '.check_status' do
    context 'without a live API (mock mode)' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:airb, :api_endpoint).and_return(nil) if defined?(Legion::Settings)
        allow(Legion::Settings).to receive(:dig).with(:airb, :credentials).and_return(nil)  if defined?(Legion::Settings)
      end

      it 'returns pending by default' do
        result = described_class.check_status(intake_id)
        expect(result).to eq('pending')
      end

      it 'returns a string status' do
        result = described_class.check_status('any-id')
        expect(result).to be_a(String)
      end
    end
  end

  describe '.sync_status' do
    let(:pending_worker) do
      double('Worker',
             worker_id:       worker_id,
             lifecycle_state: 'pending_approval',
             airb_intake_id:  intake_id)
    end

    context 'when worker is not found' do
      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: 'missing').and_return(nil)
      end

      it 'returns synced: false with reason' do
        result = described_class.sync_status('missing')
        expect(result[:synced]).to be(false)
        expect(result[:reason]).to eq('worker not found')
      end
    end

    context 'when worker is not pending approval' do
      let(:active_worker) { double('Worker', worker_id: worker_id, lifecycle_state: 'active') }

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id).and_return(active_worker)
      end

      it 'returns synced: false' do
        result = described_class.sync_status(worker_id)
        expect(result[:synced]).to be(false)
        expect(result[:reason]).to eq('not pending approval')
      end
    end

    context 'when worker is pending but has no intake_id' do
      let(:no_intake_worker) do
        double('Worker',
               worker_id:       worker_id,
               lifecycle_state: 'pending_approval')
      end

      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id)
                                                                    .and_return(no_intake_worker)
        allow(no_intake_worker).to receive(:respond_to?).with(:airb_intake_id).and_return(false)
      end

      it 'returns synced: false with no intake_id reason' do
        result = described_class.sync_status(worker_id)
        expect(result[:synced]).to be(false)
        expect(result[:reason]).to eq('no intake_id found')
      end
    end

    context 'when AIRB status is pending' do
      before do
        allow(Legion::Data::Model::DigitalWorker).to receive(:first).with(worker_id: worker_id)
                                                                    .and_return(pending_worker)
        allow(pending_worker).to receive(:respond_to?).with(:airb_intake_id).and_return(true)
        allow(described_class).to receive(:check_status).with(intake_id).and_return('pending')
      end

      it 'returns synced: false' do
        result = described_class.sync_status(worker_id)
        expect(result[:synced]).to be(false)
      end
    end
  end
end
