# frozen_string_literal: true

require 'spec_helper'
require 'legion/compliance'

RSpec.describe Legion::Compliance::PhiErasure do
  before do
    allow(Legion::Settings).to receive(:[]).with(:compliance).and_return({ phi_enabled: true })
  end

  describe '.erase' do
    context 'when all optional components are present' do
      before do
        stub_const('Legion::Crypt::Erasure', Module.new)
        stub_const('Legion::Cache', Module.new)
        allow(Legion::Crypt::Erasure).to receive(:erase_tenant).and_return({ erased: true })
        allow(Legion::Crypt::Erasure).to receive(:verify_erasure).and_return({ erased: true })
        allow(Legion::Cache).to receive(:delete)
        stub_const('Legion::Compliance::PhiAccessLog', Module.new)
        allow(Legion::Compliance::PhiAccessLog).to receive(:log_access)
      end

      it 'calls Crypt::Erasure.erase_tenant with task_id as tenant_id' do
        described_class.erase(task_id: 'task:77', reason: 'patient_request')
        expect(Legion::Crypt::Erasure).to have_received(:erase_tenant).with(tenant_id: 'task:77')
      end

      it 'calls PhiAccessLog.log_access with erasure action' do
        described_class.erase(task_id: 'task:77', reason: 'patient_request')
        expect(Legion::Compliance::PhiAccessLog).to have_received(:log_access).with(
          hash_including(action: 'erasure', resource: 'task:77', reason: 'patient_request')
        )
      end

      it 'calls Crypt::Erasure.verify_erasure' do
        described_class.erase(task_id: 'task:77', reason: 'patient_request')
        expect(Legion::Crypt::Erasure).to have_received(:verify_erasure).with(tenant_id: 'task:77')
      end

      it 'returns a result hash with erased: true' do
        result = described_class.erase(task_id: 'task:77', reason: 'patient_request')
        expect(result[:erased]).to be true
        expect(result[:task_id]).to eq('task:77')
      end
    end

    context 'when Legion::Crypt::Erasure is not defined' do
      before do
        hide_const('Legion::Crypt::Erasure') if defined?(Legion::Crypt::Erasure)
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        hide_const('Legion::Compliance::PhiAccessLog') if defined?(Legion::Compliance::PhiAccessLog)
      end

      it 'does not raise and returns partial result' do
        expect do
          result = described_class.erase(task_id: 'task:88', reason: 'test')
          expect(result[:task_id]).to eq('task:88')
        end.not_to raise_error
      end
    end

    context 'when Legion::Cache is not defined' do
      before do
        stub_const('Legion::Crypt::Erasure', Module.new)
        allow(Legion::Crypt::Erasure).to receive(:erase_tenant).and_return({ erased: true })
        allow(Legion::Crypt::Erasure).to receive(:verify_erasure).and_return({ erased: true })
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Compliance::PhiAccessLog', Module.new)
        allow(Legion::Compliance::PhiAccessLog).to receive(:log_access)
      end

      it 'skips cache purge without raising' do
        expect { described_class.erase(task_id: 'task:99', reason: 'test') }.not_to raise_error
      end
    end

    context 'when erase_tenant fails' do
      before do
        stub_const('Legion::Crypt::Erasure', Module.new)
        allow(Legion::Crypt::Erasure).to receive(:erase_tenant).and_return({ erased: false, error: 'vault unavailable' })
        allow(Legion::Crypt::Erasure).to receive(:verify_erasure).and_return({ erased: false })
        hide_const('Legion::Cache') if defined?(Legion::Cache)
        stub_const('Legion::Compliance::PhiAccessLog', Module.new)
        allow(Legion::Compliance::PhiAccessLog).to receive(:log_access)
      end

      it 'returns erased: false' do
        result = described_class.erase(task_id: 'task:bad', reason: 'test')
        expect(result[:erased]).to be false
      end
    end
  end
end
