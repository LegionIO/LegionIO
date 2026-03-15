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

  describe 'worker not found' do
    it 'shows error and returns without calling transition!' do
      stub_find_worker(nil)

      expect(Legion::DigitalWorker::Lifecycle).not_to receive(:transition!)
      expect(out).to receive(:error).with(/not found/i)

      build_command.pause('nonexistent-id')
    end
  end
end
