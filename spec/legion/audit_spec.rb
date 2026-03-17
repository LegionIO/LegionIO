# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit'

RSpec.describe Legion::Audit do
  let(:valid_opts) do
    {
      event_type:   'runner_execution',
      principal_id: 'worker-123',
      action:       'execute',
      resource:     'MyRunner/my_function',
      source:       'amqp'
    }
  end

  describe '.record' do
    context 'when transport is available and lex-audit is loaded' do
      let(:message_double) { instance_double('Message', publish: true) }

      before do
        stub_const('Legion::Transport', Module.new)
        stub_const('Legion::Extensions::Audit::Transport::Messages::Audit', Class.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ hostname: 'node-01' })
        allow(Legion::Extensions::Audit::Transport::Messages::Audit).to receive(:new).and_return(message_double)
      end

      it 'publishes a message' do
        described_class.record(**valid_opts)
        expect(message_double).to have_received(:publish)
      end

      it 'stamps node from settings' do
        described_class.record(**valid_opts)
        expect(Legion::Extensions::Audit::Transport::Messages::Audit).to have_received(:new).with(
          hash_including(node: 'node-01')
        )
      end

      it 'stamps created_at as ISO8601' do
        described_class.record(**valid_opts)
        expect(Legion::Extensions::Audit::Transport::Messages::Audit).to have_received(:new).with(
          hash_including(created_at: match(/^\d{4}-\d{2}-\d{2}T/))
        )
      end
    end

    context 'when transport is not connected' do
      before do
        stub_const('Legion::Transport', Module.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: false })
      end

      it 'silently returns nil' do
        expect(described_class.record(**valid_opts)).to be_nil
      end
    end

    context 'when lex-audit message class is not defined' do
      before do
        stub_const('Legion::Transport', Module.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        # Legion::Extensions::Audit::Transport::Messages::Audit is NOT defined
      end

      it 'silently returns nil' do
        expect(described_class.record(**valid_opts)).to be_nil
      end
    end

    context 'when publishing raises an error' do
      let(:message_double) { instance_double('Message') }

      before do
        stub_const('Legion::Transport', Module.new)
        stub_const('Legion::Extensions::Audit::Transport::Messages::Audit', Class.new)
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ connected: true })
        allow(Legion::Settings).to receive(:[]).with(:client).and_return({ hostname: 'node-01' })
        allow(Legion::Extensions::Audit::Transport::Messages::Audit).to receive(:new).and_return(message_double)
        allow(message_double).to receive(:publish).and_raise(StandardError, 'connection lost')
      end

      it 'never raises' do
        expect { described_class.record(**valid_opts) }.not_to raise_error
      end
    end
  end

  describe '.recent_for' do
    context 'when Legion::Data::Model::AuditLog is not defined' do
      it 'returns an empty array' do
        expect(described_class.recent_for(principal_id: 'w-1')).to eq([])
      end
    end

    context 'when Legion::Data::Model::AuditLog is defined' do
      let(:model_double) { class_double('Legion::Data::Model::AuditLog') }
      let(:dataset) { instance_double('Sequel::Dataset') }

      before do
        stub_const('Legion::Data::Model::AuditLog', model_double)
        allow(model_double).to receive(:where).and_return(dataset)
        allow(dataset).to receive(:where).and_return(dataset)
        allow(dataset).to receive(:all).and_return([double('row')])
      end

      it 'delegates to the model with principal_id filter' do
        result = described_class.recent_for(principal_id: 'w-1', window: 60)
        expect(result).not_to be_empty
      end

      it 'applies event_type filter when given' do
        described_class.recent_for(principal_id: 'w-1', event_type: 'runner_execution')
        expect(dataset).to have_received(:where).with(event_type: 'runner_execution')
      end

      it 'applies status filter when given' do
        described_class.recent_for(principal_id: 'w-1', status: 'failure')
        expect(dataset).to have_received(:where).with(status: 'failure')
      end
    end
  end

  describe '.count_for' do
    context 'when Legion::Data::Model::AuditLog is not defined' do
      it 'returns 0' do
        expect(described_class.count_for(principal_id: 'w-1')).to eq(0)
      end
    end

    context 'when Legion::Data::Model::AuditLog is defined' do
      let(:model_double) { class_double('Legion::Data::Model::AuditLog') }
      let(:dataset) { instance_double('Sequel::Dataset') }

      before do
        stub_const('Legion::Data::Model::AuditLog', model_double)
        allow(model_double).to receive(:where).and_return(dataset)
        allow(dataset).to receive(:where).and_return(dataset)
        allow(dataset).to receive(:count).and_return(7)
      end

      it 'returns the model count' do
        expect(described_class.count_for(principal_id: 'w-1')).to eq(7)
      end
    end
  end

  describe '.failure_count_for' do
    it 'delegates to count_for with status: failure' do
      allow(described_class).to receive(:count_for).and_return(3)
      described_class.failure_count_for(principal_id: 'w-1')
      expect(described_class).to have_received(:count_for).with(
        principal_id: 'w-1', window: 3600, status: 'failure'
      )
    end
  end

  describe '.success_count_for' do
    it 'delegates to count_for with status: success' do
      allow(described_class).to receive(:count_for).and_return(5)
      described_class.success_count_for(principal_id: 'w-1')
      expect(described_class).to have_received(:count_for).with(
        principal_id: 'w-1', window: 3600, status: 'success'
      )
    end
  end

  describe '.resources_for' do
    context 'when Legion::Data::Model::AuditLog is not defined' do
      it 'returns an empty array' do
        expect(described_class.resources_for(principal_id: 'w-1')).to eq([])
      end
    end
  end

  describe '.recent' do
    context 'when Legion::Data::Model::AuditLog is not defined' do
      it 'returns an empty array' do
        expect(described_class.recent).to eq([])
      end
    end
  end
end
