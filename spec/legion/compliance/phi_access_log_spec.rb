# frozen_string_literal: true

require 'spec_helper'
require 'legion/compliance'

RSpec.describe Legion::Compliance::PhiAccessLog do
  before do
    Legion::Settings.merge_settings(:compliance, Legion::Compliance::DEFAULTS)
  end

  describe '.log_access' do
    context 'when phi_enabled is true and Legion::Audit is defined' do
      before do
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record)
      end

      it 'calls Legion::Audit.record with event_type phi_access' do
        described_class.log_access(
          resource: 'task:42',
          action:   'read',
          actor:    'worker:7',
          reason:   'treatment'
        )

        expect(Legion::Audit).to have_received(:record).with(
          hash_including(
            event_type:   'phi_access',
            action:       'read',
            resource:     'task:42',
            principal_id: 'worker:7'
          )
        )
      end

      it 'passes reason in detail' do
        described_class.log_access(
          resource: 'task:1',
          action:   'write',
          actor:    'system',
          reason:   'payment'
        )

        expect(Legion::Audit).to have_received(:record).with(
          hash_including(detail: hash_including(reason: 'payment'))
        )
      end
    end

    context 'when phi_enabled is false' do
      before do
        allow(Legion::Compliance).to receive(:phi_enabled?).and_return(false)
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record)
      end

      it 'does not call Legion::Audit.record' do
        described_class.log_access(resource: 'task:1', action: 'read', actor: 'x', reason: 'y')
        expect(Legion::Audit).not_to have_received(:record)
      end
    end

    context 'when Legion::Audit is not defined' do
      before do
        hide_const('Legion::Audit')
      end

      it 'does not raise' do
        expect do
          described_class.log_access(resource: 'task:1', action: 'read', actor: 'x', reason: 'y')
        end.not_to raise_error
      end
    end
  end
end
