# frozen_string_literal: true

require 'spec_helper'
require 'legion/audit'
require 'legion/runner'

# Minimal runner class for testing
module TestRunners
  module AuditTest
    def self.succeed(**_args)
      { result: 'ok' }
    end

    def self.fail_hard(**_args)
      raise StandardError, 'boom'
    end

    def self.handle_exception(exception, **_opts); end
  end
end

RSpec.describe 'Runner.run audit integration' do
  before do
    stub_const('Legion::Exception::HandledTask', Class.new(StandardError)) unless defined?(Legion::Exception::HandledTask)
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Runner::Status).to receive(:generate_task_id).and_return({ task_id: 1 })
    allow(Legion::Runner::Status).to receive(:update)
    allow(Legion::Transport::Messages::CheckSubtask).to receive_message_chain(:new, :publish)
  end

  context 'when Legion::Audit is defined' do
    before do
      allow(Legion::Audit).to receive(:record)
    end

    it 'calls Legion::Audit.record on successful execution' do
      Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :succeed, check_subtask: false)
      expect(Legion::Audit).to have_received(:record).with(
        hash_including(
          event_type: 'runner_execution',
          action:     'execute',
          resource:   'TestRunners::AuditTest/succeed',
          status:     'success'
        )
      )
    end

    it 'includes duration_ms in the audit record' do
      Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :succeed, check_subtask: false)
      expect(Legion::Audit).to have_received(:record).with(
        hash_including(duration_ms: a_kind_of(Integer))
      )
    end

    it 'records failure status on exception' do
      Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :fail_hard,
                         check_subtask: false, catch_exceptions: true)
      expect(Legion::Audit).to have_received(:record).with(
        hash_including(status: 'failure')
      )
    end

    it 'includes error message on exception' do
      Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :fail_hard,
                         check_subtask: false, catch_exceptions: true)
      expect(Legion::Audit).to have_received(:record).with(
        hash_including(detail: hash_including(error: 'boom'))
      )
    end

    it 'uses principal_id from opts when provided' do
      Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :succeed,
                         check_subtask: false, principal_id: 'worker-42')
      expect(Legion::Audit).to have_received(:record).with(
        hash_including(principal_id: 'worker-42')
      )
    end

    it 'still works when audit publishing raises' do
      allow(Legion::Audit).to receive(:record).and_raise(StandardError, 'audit down')
      result = Legion::Runner.run(runner_class: TestRunners::AuditTest, function: :succeed, check_subtask: false)
      expect(result[:success]).to be true
    end
  end
end
