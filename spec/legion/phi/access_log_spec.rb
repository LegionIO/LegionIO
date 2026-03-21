# frozen_string_literal: true

require 'spec_helper'
require 'legion/phi/access_log'

RSpec.describe Legion::Phi::AccessLog do
  let(:valid_params) do
    {
      actor:      'worker-007',
      resource:   'patient/p-12345',
      action:     'read',
      phi_fields: %i[ssn dob],
      reason:     'treatment'
    }
  end

  # ---------------------------------------------------------------------------
  # .log_access
  # ---------------------------------------------------------------------------
  describe '.log_access' do
    context 'when neither Legion::Audit nor Legion::Logging is defined' do
      before do
        hide_const('Legion::Audit')
        hide_const('Legion::Logging')
      end

      it 'returns true without raising' do
        expect { described_class.log_access(**valid_params) }.not_to raise_error
        expect(described_class.log_access(**valid_params)).to be true
      end
    end

    context 'when Legion::Audit is defined' do
      before do
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record)
      end

      it 'calls Legion::Audit.record with phi event_type' do
        described_class.log_access(**valid_params)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(event_type: 'phi_access', principal_id: 'worker-007')
        )
      end

      it 'includes resource in the audit call' do
        described_class.log_access(**valid_params)
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(resource: 'patient/p-12345')
        )
      end

      it 'returns true' do
        expect(described_class.log_access(**valid_params)).to be true
      end
    end

    context 'when Legion::Logging is defined but Legion::Audit is not' do
      before do
        hide_const('Legion::Audit')
        stub_const('Legion::Logging', Module.new)
        allow(Legion::Logging).to receive(:info)
      end

      it 'logs via Legion::Logging' do
        described_class.log_access(**valid_params)
        expect(Legion::Logging).to have_received(:info).with(match(/PHI ACCESS/))
      end
    end

    context 'when Legion::Audit.record raises' do
      before do
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record).and_raise(StandardError, 'transport down')
        # Define Legion::Logging with a real warn singleton method so emit_warning works
        logging_mod = Module.new
        logging_mod.define_singleton_method(:warn) { nil }
        stub_const('Legion::Logging', logging_mod)
        allow(Legion::Logging).to receive(:warn)
      end

      it 'does not raise' do
        expect { described_class.log_access(**valid_params) }.not_to raise_error
      end

      it 'emits a warning via Legion::Logging' do
        described_class.log_access(**valid_params)
        expect(Legion::Logging).to have_received(:warn).with(match(/PHI audit record failed/))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .log_access!
  # ---------------------------------------------------------------------------
  describe '.log_access!' do
    context 'when Legion::Audit is defined and works' do
      before do
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record)
      end

      it 'returns true' do
        expect(described_class.log_access!(**valid_params)).to be true
      end

      it 'calls Legion::Audit.record' do
        described_class.log_access!(**valid_params)
        expect(Legion::Audit).to have_received(:record)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .recent_access
  # ---------------------------------------------------------------------------
  describe '.recent_access' do
    context 'when neither Legion::Audit nor Legion::Data is defined' do
      before do
        hide_const('Legion::Audit')
        hide_const('Legion::Data')
      end

      it 'returns an empty array' do
        expect(described_class.recent_access(resource: 'patient/p-1')).to eq([])
      end
    end

    context 'when Legion::Audit and Legion::Data::Model::AuditLog are defined' do
      let(:fake_record) { { event_type: 'phi_access', resource: 'patient/p-1', principal_id: 'w-1' } }

      before do
        stub_const('Legion::Audit', Module.new)
        stub_const('Legion::Data', Module.new)
        stub_const('Legion::Data::Model', Module.new)
        stub_const('Legion::Data::Model::AuditLog', Class.new)
        allow(Legion::Audit).to receive(:recent).and_return([fake_record])
      end

      it 'delegates to Legion::Audit.recent with event_type filter' do
        result = described_class.recent_access(resource: 'patient/p-1', limit: 10)
        expect(Legion::Audit).to have_received(:recent).with(
          hash_including(limit: 10, resource: 'patient/p-1', event_type: 'phi_access')
        )
        expect(result).to eq([fake_record])
      end
    end
  end
end
