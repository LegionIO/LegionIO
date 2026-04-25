# frozen_string_literal: true

require 'spec_helper'

# Stub dependencies
unless defined?(Legion::DigitalWorker::Registry)
  module Legion
    module DigitalWorker
      module Registry
        class WorkerNotFound < StandardError; end
        class WorkerNotActive < StandardError; end
        class InsufficientConsent < StandardError; end
      end
    end
  end
end

RSpec.describe Legion::Ingress do
  let(:runner_class) { 'Legion::Test::Runners::Example' }
  let(:function) { :do_work }

  before do
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Runner).to receive(:run).and_return({ success: true, status: 'task.completed' })
    if defined?(Legion::Rbac)
      allow(Legion::Rbac).to receive(:authorize_execution!)
      stub_const('Legion::Rbac::Principal', double(local_admin: double('Principal')))
    end
  end

  describe '.run' do
    context 'without worker_id' do
      it 'does not call Registry.validate_execution!' do
        expect(Legion::DigitalWorker::Registry).not_to receive(:validate_execution!)
        described_class.run(payload: {}, runner_class: runner_class, function: function)
      end

      it 'proceeds to Runner.run' do
        expect(Legion::Runner).to receive(:run)
        described_class.run(payload: {}, runner_class: runner_class, function: function)
      end
    end

    context 'with worker_id and Registry defined' do
      it 'calls Registry.validate_execution! with the worker_id' do
        expect(Legion::DigitalWorker::Registry).to receive(:validate_execution!)
          .with(worker_id: 'dw-123', required_consent: nil)
        described_class.run(payload: { worker_id: 'dw-123' }, runner_class: runner_class, function: function)
      end

      it 'checks registration before execution' do
        call_order = []
        allow(Legion::DigitalWorker::Registry).to receive(:validate_execution!) { call_order << :registry }
        allow(Legion::Runner).to receive(:run) do
          call_order << :runner
          { success: true }
        end
        described_class.run(payload: { worker_id: 'dw-123' }, runner_class: runner_class, function: function)
        expect(call_order).to eq(%i[registry runner])
      end
    end

    context 'when worker is not registered' do
      before do
        allow(Legion::DigitalWorker::Registry).to receive(:validate_execution!)
          .and_raise(Legion::DigitalWorker::Registry::WorkerNotFound, 'no registered worker with id dw-999')
      end

      it 'returns a structured error' do
        result = described_class.run(payload: { worker_id: 'dw-999' }, runner_class: runner_class, function: function)
        expect(result[:success]).to be false
        expect(result[:status]).to eq('task.blocked')
        expect(result[:error][:code]).to eq('worker_not_found')
      end

      it 'does not call Runner.run' do
        expect(Legion::Runner).not_to receive(:run)
        described_class.run(payload: { worker_id: 'dw-999' }, runner_class: runner_class, function: function)
      end
    end

    context 'when worker is not active' do
      before do
        allow(Legion::DigitalWorker::Registry).to receive(:validate_execution!)
          .and_raise(Legion::DigitalWorker::Registry::WorkerNotActive, 'worker dw-456 is paused')
      end

      it 'returns a structured error with worker_not_active code' do
        result = described_class.run(payload: { worker_id: 'dw-456' }, runner_class: runner_class, function: function)
        expect(result[:success]).to be false
        expect(result[:error][:code]).to eq('worker_not_active')
      end
    end

    context 'when consent is insufficient' do
      before do
        allow(Legion::DigitalWorker::Registry).to receive(:validate_execution!)
          .and_raise(Legion::DigitalWorker::Registry::InsufficientConsent, 'consent too low')
      end

      it 'returns a structured error with insufficient_consent code' do
        result = described_class.run(
          payload: { worker_id: 'dw-789', required_consent: 'autonomous' },
          runner_class: runner_class, function: function
        )
        expect(result[:success]).to be false
        expect(result[:error][:code]).to eq('insufficient_consent')
      end
    end

    context 'with required_consent in payload' do
      it 'passes required_consent to validate_execution!' do
        expect(Legion::DigitalWorker::Registry).to receive(:validate_execution!)
          .with(worker_id: 'dw-123', required_consent: 'autonomous')
        described_class.run(
          payload: { worker_id: 'dw-123', required_consent: 'autonomous' },
          runner_class: runner_class, function: function
        )
      end
    end

    context 'input validation' do
      it 'rejects invalid runner_class format' do
        result = described_class.run(
          payload: {}, runner_class: '../../../etc/passwd', function: 'read', source: 'test'
        )
        expect(result[:success]).to be false
        expect(result[:error][:code]).to eq('invalid_runner_class')
      end

      it 'rejects invalid function format' do
        result = described_class.run(
          payload: {}, runner_class: 'Legion::Test::Runner',
          function: 'system("rm -rf /")', source: 'test'
        )
        expect(result[:success]).to be false
        expect(result[:error][:code]).to eq('invalid_function')
      end

      it 'accepts valid runner_class and function formats' do
        result = described_class.run(
          payload: {}, runner_class: 'Legion::Test::Runner', function: 'do_thing', source: 'test'
        )
        expect(result[:error]).to be_nil
      end
    end

    context 'when an extension handle is quiescing' do
      before do
        Legion::Extensions.reset_runtime_handles!
        Legion::Extensions.register_extension_handle('lex-example', state: :running, reload_state: :updating)
      end

      after { Legion::Extensions.reset_runtime_handles! }

      it 'blocks runner dispatch for that extension before Runner.run' do
        result = described_class.run(
          payload:      {},
          runner_class: 'Legion::Extensions::Example::Runners::Worker',
          function:     'do_work',
          source:       'test'
        )

        expect(result[:success]).to be false
        expect(result[:status]).to eq('task.blocked')
        expect(result[:error][:code]).to eq('extension_quiescing')
        expect(Legion::Runner).not_to have_received(:run)
      end
    end
  end
end
