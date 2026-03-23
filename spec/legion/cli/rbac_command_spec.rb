# frozen_string_literal: true

require 'spec_helper'
require 'thor'
require 'sequel'
require 'legion/cli/output'
require 'legion/cli/connection'
require 'legion/cli/error'
require 'legion/cli/rbac_command'

RSpec.describe Legion::CLI::Rbac do
  let(:out) do
    instance_double(Legion::CLI::Output::Formatter,
                    success: nil, error: nil, warn: nil,
                    table: nil, json: nil, header: nil)
  end

  before do
    allow_any_instance_of(described_class).to receive(:formatter).and_return(out)
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_settings)
    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  def stub_rbac_setup
    rbac_mod = Module.new do
      def self.setup; end
      def self.role_index = {}
    end
    stub_const('Legion::Rbac', rbac_mod) unless defined?(Legion::Rbac)
    allow(Legion::Rbac).to receive(:setup)
    allow_any_instance_of(described_class).to receive(:require).and_call_original
    allow_any_instance_of(described_class).to receive(:require).with('legion/rbac').and_return(true)
  end

  describe 'roles' do
    it 'lists roles in a table' do
      stub_rbac_setup
      allow(Legion::Rbac).to receive(:role_index).and_return({})
      expect(out).to receive(:table).with(%w[Role Description CrossTeam], [])
      described_class.start(%w[roles])
    end

    it 'outputs JSON when requested' do
      stub_rbac_setup
      allow(Legion::Rbac).to receive(:role_index).and_return({})
      expect(out).to receive(:json)
      described_class.start(%w[roles --json])
    end
  end

  describe 'show' do
    it 'displays role details' do
      stub_rbac_setup
      fake_role = double('role',
                         name:        'admin',
                         description: 'Full access',
                         cross_team?: true,
                         permissions: [],
                         deny_rules:  [])
      allow(Legion::Rbac).to receive(:role_index).and_return({ admin: fake_role })

      expect(out).to receive(:header).with('Role: admin')
      expect { described_class.start(%w[show admin]) }.to output(/Full access/).to_stdout
    end

    it 'reports error for unknown role' do
      stub_rbac_setup
      allow(Legion::Rbac).to receive(:role_index).and_return({})
      expect(out).to receive(:error).with(/Role not found/)
      described_class.start(%w[show nonexistent])
    end
  end

  describe 'assignments' do
    it 'lists role assignments' do
      stub_rbac_setup
      model = class_double('Legion::Data::Model::RbacRoleAssignment')
      stub_const('Legion::Data::Model::RbacRoleAssignment', model)

      fake_dataset = double('dataset')
      allow(model).to receive(:dataset).and_return(fake_dataset)
      allow(fake_dataset).to receive(:all).and_return([])

      expect(out).to receive(:table)
      described_class.start(%w[assignments])
    end
  end

  describe 'assign' do
    it 'creates a role assignment' do
      stub_rbac_setup
      model = class_double('Legion::Data::Model::RbacRoleAssignment')
      stub_const('Legion::Data::Model::RbacRoleAssignment', model)

      fake_record = double('record', id: 7)
      allow(model).to receive(:create).and_return(fake_record)

      expect(out).to receive(:success).with(/Assigned operator to user-42/)
      described_class.start(%w[assign user-42 operator])
    end
  end

  describe 'revoke' do
    it 'removes role assignments' do
      stub_rbac_setup
      model = class_double('Legion::Data::Model::RbacRoleAssignment')
      stub_const('Legion::Data::Model::RbacRoleAssignment', model)

      fake_dataset = double('dataset')
      allow(model).to receive(:where).and_return(fake_dataset)
      allow(fake_dataset).to receive(:count).and_return(2)
      allow(fake_dataset).to receive(:destroy)

      expect(out).to receive(:success).with(/Revoked 2/)
      described_class.start(%w[revoke user-42 operator])
    end
  end

  describe 'check' do
    it 'evaluates authorization' do
      stub_rbac_setup

      principal_class = Class.new do
        def initialize(**); end
      end
      stub_const('Legion::Rbac::Principal', principal_class)

      engine = Module.new do
        def self.evaluate(**) = { allowed: true, reason: 'admin role' }
      end
      stub_const('Legion::Rbac::PolicyEngine', engine)

      expect { described_class.start(%w[check user-1 tasks/42 --action read]) }.to output(/ALLOWED/).to_stdout
    end

    it 'shows DENIED for unauthorized access' do
      stub_rbac_setup

      principal_class = Class.new do
        def initialize(**); end
      end
      stub_const('Legion::Rbac::Principal', principal_class)

      engine = Module.new do
        def self.evaluate(**) = { allowed: false, reason: 'no matching permission' }
      end
      stub_const('Legion::Rbac::PolicyEngine', engine)

      expect { described_class.start(%w[check user-1 secrets/key]) }.to output(/DENIED/).to_stdout
    end
  end
end
