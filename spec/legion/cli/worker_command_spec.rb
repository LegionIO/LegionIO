# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/worker_command'
require 'legion/digital_worker/lifecycle'

RSpec.describe Legion::CLI::Worker do
  let(:worker_id)    { 'abc-1234-5678' }
  let(:worker_model) { class_double('Legion::Data::Model::DigitalWorker') }
  let(:worker)       { double('worker', worker_id: worker_id, name: 'TestBot', lifecycle_state: 'active') }
  let(:out)          { instance_double(Legion::CLI::Output::Formatter) }

  before do
    stub_const('Legion::Data::Model::DigitalWorker', worker_model)

    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:spacer)
    allow(out).to receive(:detail)

    allow(Legion::CLI::Connection).to receive(:ensure_data)
    allow(Legion::CLI::Connection).to receive(:shutdown)
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
  end

  def build_command(opts = {})
    described_class.new([], opts.merge(json: false, no_color: true, verbose: false))
  end

  def stub_find_worker(result)
    allow(worker_model).to receive(:first).and_return(result)
    sequel_stub = double('Sequel')
    allow(sequel_stub).to receive(:like).and_return(double('like_expr'))
    stub_const('Sequel', sequel_stub)
    allow(worker_model).to receive(:where).and_return(double('ds', first: nil))
  end

  describe '#pause' do
    it 'passes authority_verified: true to transition!' do
      stub_find_worker(worker)
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker,
        to_state:           'paused',
        by:                 'cli',
        reason:             nil,
        authority_verified: true
      ).and_return(worker)

      build_command.pause(worker_id)
    end

    it 'shows success message on successful transition' do
      stub_find_worker(worker)
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!).and_return(worker)

      expect(out).to receive(:success).with(/paused/)
      build_command.pause(worker_id)
    end

    it 'shows user-friendly error when AuthorityRequired is raised' do
      stub_find_worker(worker)
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
        .and_raise(Legion::DigitalWorker::Lifecycle::AuthorityRequired, 'active -> paused requires owner_or_manager')

      expect(out).to receive(:error).with(/authority|permission/i)
      build_command.pause(worker_id)
    end

    it 'shows user-friendly error when GovernanceRequired is raised' do
      stub_find_worker(worker)
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
        .and_raise(Legion::DigitalWorker::Lifecycle::GovernanceRequired, 'active -> terminated requires council_approval')

      expect(out).to receive(:error).with(/governance|approval/i)
      build_command.pause(worker_id)
    end
  end

  describe '#activate' do
    it 'passes authority_verified: true to transition!' do
      stub_find_worker(worker)
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker,
        to_state:           'active',
        by:                 'cli',
        reason:             nil,
        authority_verified: true
      ).and_return(worker)

      build_command.activate(worker_id)
    end
  end

  describe '#retire' do
    it 'passes authority_verified: true to transition!' do
      stub_find_worker(worker)
      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker,
        to_state:           'retired',
        by:                 'cli',
        reason:             nil,
        authority_verified: true
      ).and_return(worker)

      build_command.retire(worker_id)
    end
  end

  describe '#terminate' do
    it 'passes governance_override: true after user confirms' do
      stub_find_worker(worker)
      allow($stdin).to receive(:gets).and_return("yes\n")

      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker,
        to_state:            'terminated',
        by:                  'cli',
        reason:              nil,
        governance_override: true
      ).and_return(worker)

      build_command(yes: false).terminate(worker_id)
    end

    it 'skips confirmation prompt with --yes flag and passes governance_override: true' do
      stub_find_worker(worker)

      expect(Legion::DigitalWorker::Lifecycle).to receive(:transition!).with(
        worker,
        to_state:            'terminated',
        by:                  'cli',
        reason:              nil,
        governance_override: true
      ).and_return(worker)

      build_command(yes: true).terminate(worker_id)
    end

    it 'aborts without calling transition! when user types something other than yes' do
      allow($stdin).to receive(:gets).and_return("no\n")
      expect(Legion::DigitalWorker::Lifecycle).not_to receive(:transition!)
      build_command(yes: false).terminate(worker_id)
    end

    it 'shows user-friendly error when GovernanceRequired is raised' do
      stub_find_worker(worker)
      allow($stdin).to receive(:gets).and_return("yes\n")
      allow(Legion::DigitalWorker::Lifecycle).to receive(:transition!)
        .and_raise(Legion::DigitalWorker::Lifecycle::GovernanceRequired,
                   'retired -> terminated requires council_approval')

      expect(out).to receive(:error).with(/governance|approval/i)
      build_command(yes: false).terminate(worker_id)
    end
  end

  describe '#create' do
    let(:mock_worker) { double('worker', to_hash: { worker_id: 'uuid-1', name: 'test-worker' }) }

    before do
      allow(worker_model).to receive(:create).and_return(mock_worker)
    end

    it 'creates a worker in bootstrap state with required options' do
      expect(worker_model).to receive(:create).with(hash_including(
                                                      lifecycle_state: 'bootstrap',
                                                      trust_score:     0.0,
                                                      entra_app_id:    'app-123'
                                                    ))
      build_command(entra_app_id: 'app-123', owner_msid: 'user@uhg.com',
                    extension: 'lex-github', risk_tier: 'low', consent_tier: 'supervised').create('test-worker')
    end

    it 'generates a UUID worker_id' do
      expect(worker_model).to receive(:create).with(hash_including(
                                                      worker_id: match(/\A[0-9a-f-]{36}\z/)
                                                    ))
      build_command(entra_app_id: 'app-123', owner_msid: 'user@uhg.com',
                    extension: 'lex-github', risk_tier: 'low', consent_tier: 'supervised').create('test-worker')
    end

    it 'includes optional team and manager when provided' do
      expect(worker_model).to receive(:create).with(hash_including(
                                                      team: 'grid-team', manager_msid: 'mgr@uhg.com', risk_tier: 'high'
                                                    ))
      build_command(entra_app_id: 'app-123', owner_msid: 'user@uhg.com', extension: 'lex-github',
                    team: 'grid-team', manager_msid: 'mgr@uhg.com',
                    risk_tier: 'high', consent_tier: 'supervised').create('test-worker')
    end

    it 'outputs JSON when --json is set' do
      expect(out).to receive(:json).with(hash_including(worker_id: 'uuid-1'))
      described_class.new([], json: true, no_color: true, verbose: false,
                              entra_app_id: 'app-123', owner_msid: 'user@uhg.com',
                              extension: 'lex-github', risk_tier: 'low', consent_tier: 'supervised').create('test-worker')
    end

    it 'outputs duplicate error on UniqueConstraintViolation' do
      stub_const('Sequel::UniqueConstraintViolation', Class.new(StandardError))
      allow(worker_model).to receive(:create)
        .and_raise(Sequel::UniqueConstraintViolation.new('duplicate'))
      expect(out).to receive(:error).with(/already exists/)
      build_command(entra_app_id: 'dup-app', owner_msid: 'user@uhg.com',
                    extension: 'lex-github', risk_tier: 'low', consent_tier: 'supervised').create('test-worker')
    end

    context 'with client_secret and Vault available' do
      let(:vault_mod) do
        Module.new do
          def self.store_client_secret(**) = true
          def self.vault_available? = true
        end
      end

      before { stub_const('Legion::Extensions::Identity::Helpers::VaultSecrets', vault_mod) }

      it 'stores the client secret in Vault' do
        expect(vault_mod).to receive(:store_client_secret)
          .with(hash_including(worker_id: match(/\A[0-9a-f-]{36}\z/), client_secret: 'secret-value'))
        build_command(entra_app_id: 'app-123', owner_msid: 'user@uhg.com',
                      extension: 'lex-github', client_secret: 'secret-value',
                      risk_tier: 'low', consent_tier: 'supervised').create('test-worker')
      end
    end
  end

  describe 'worker not found' do
    it 'shows error and returns without calling transition!' do
      stub_find_worker(nil)

      expect(Legion::DigitalWorker::Lifecycle).not_to receive(:transition!)
      expect(out).to receive(:error).with(/not found/i)

      build_command.pause('nonexistent-id')
    end
  end
end
