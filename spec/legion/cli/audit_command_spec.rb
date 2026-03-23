# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sequel'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/audit_command'

RSpec.describe Legion::CLI::Audit do
  before do
    allow(Legion::CLI::Connection).to receive(:ensure_settings)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  describe 'list' do
    it 'queries audit log and renders records' do
      audit_model = class_double('Legion::Data::Model::AuditLog')
      stub_const('Legion::Data::Model::AuditLog', audit_model)

      fake_record = double('audit_record',
                           created_at:   Time.new(2026, 3, 15),
                           event_type:   'task.created',
                           principal_id: 'user-1',
                           action:       'create',
                           resource:     'task/42',
                           status:       'success')

      fake_dataset = double('dataset')
      allow(audit_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:all).and_return([fake_record])

      expect { described_class.start(%w[list]) }.to output(/task\.created/).to_stdout
    end

    it 'applies event_type filter' do
      audit_model = class_double('Legion::Data::Model::AuditLog')
      stub_const('Legion::Data::Model::AuditLog', audit_model)

      fake_dataset = double('dataset')
      allow(audit_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:all).and_return([])

      expect(fake_dataset).to receive(:where).with(event_type: 'auth.login')
      expect { described_class.start(%w[list --event_type auth.login]) }.to output(/0 records/).to_stdout
    end

    it 'outputs JSON when --json flag is set' do
      audit_model = class_double('Legion::Data::Model::AuditLog')
      stub_const('Legion::Data::Model::AuditLog', audit_model)

      fake_record = double('audit_record', values: { id: 1, event_type: 'test' })
      fake_dataset = double('dataset')
      allow(audit_model).to receive(:order).and_return(fake_dataset)
      allow(fake_dataset).to receive(:limit).and_return(fake_dataset)
      allow(fake_dataset).to receive(:all).and_return([fake_record])

      expect { described_class.start(%w[list --json]) }.to output(/test/).to_stdout
    end
  end

  describe 'verify' do
    it 'reports lex-audit not loaded when runner undefined' do
      expect { described_class.start(%w[verify]) }.to raise_error(SystemExit)
    end

    it 'reports valid chain' do
      runner_mod = Module.new do
        def verify
          { valid: true, records_checked: 100 }
        end
      end
      stub_const('Legion::Extensions::Audit::Runners::Audit', runner_mod)

      expect { described_class.start(%w[verify]) }.to output(/valid.*100/).to_stdout
    end

    it 'reports broken chain' do
      runner_mod = Module.new do
        def verify
          { valid: false, break_at: 55, records_checked: 54 }
        end
      end
      stub_const('Legion::Extensions::Audit::Runners::Audit', runner_mod)

      expect { described_class.start(%w[verify]) }.to raise_error(SystemExit)
    end
  end
end
