# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner'

RSpec.describe Legion::Runner do
  let(:write_error) { StandardError.new('database write failed') }
  let(:persistence_runner) do
    error = write_error
    Module.new do
      define_singleton_method(:persist) { |**| raise error }
    end
  end

  before do
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Audit).to receive(:record) if defined?(Legion::Audit)
  end

  it 'propagates the original write failure instead of returning success from cleanup' do
    expect do
      described_class.run(runner_class: persistence_runner, function: :persist,
                          generate_task: false, check_subtask: false)
    end.to(raise_error { |error| expect(error).to equal(write_error) })
  end

  it 'preserves the original failure when the runner error hook reports it handled' do
    persistence_runner.define_singleton_method(:handle_runner_exception) do |*_args, **_opts|
      raise Legion::Exception::HandledTask
    end

    expect do
      described_class.run(runner_class: persistence_runner, function: :persist,
                          generate_task: false, check_subtask: false)
    end.to(raise_error { |error| expect(error).to equal(write_error) })
  end

  it 'returns exception details when the caller explicitly opts into catching failures' do
    outcome = described_class.run(runner_class: persistence_runner, function: :persist,
                                  generate_task: false, check_subtask: false, catch_exceptions: true)

    expect(outcome).to include(status: 'task.exception', result: include(success: false, error: include(message: write_error.message)))
  end

  it 'preserves the runner error when recording its failure also raises' do
    allow(Legion::Runner::Status).to receive(:update).and_raise(IOError, 'status write failed')

    expect do
      described_class.run(runner_class: persistence_runner, function: :persist, task_id: 123,
                          generate_task: false, check_subtask: false)
    end.to(raise_error { |error| expect(error).to equal(write_error) })
  end

  it 'propagates status persistence errors after a successful runner' do
    persistence_runner.define_singleton_method(:succeed) { |**| { success: true } }
    allow(Legion::Runner::Status).to receive(:update).and_raise(write_error)

    expect do
      described_class.run(runner_class: persistence_runner, function: :succeed, task_id: 123,
                          generate_task: false, check_subtask: false)
    end.to(raise_error { |error| expect(error).to equal(write_error) })
  end

  it 'rejects model or other non-Hash results at the runner boundary' do
    persistence_runner.define_singleton_method(:invalid_result) { |**| Object.new }

    expect do
      described_class.run(runner_class: persistence_runner, function: :invalid_result,
                          generate_task: false, check_subtask: false)
    end.to raise_error(TypeError, 'runner functions must return a Hash')
  end
end
