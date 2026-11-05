# frozen_string_literal: true

require 'spec_helper'
require 'legion/data'
require 'legion/runner'
require 'legion/extensions/helpers/task'

RSpec.describe 'Runner completion and continuation' do
  let(:runner) do
    Module.new do
      def self.succeed(**args)
        { success: true, answer: args[:input], received_task_id: args[:task_id] }
      end

      def self.fail_result(**)
        { success: false, status: 'task.completed', error: 'business rejection' }
      end
    end
  end
  let(:message) { instance_double(Legion::Transport::Messages::CheckSubtask, publish!: true) }

  around do |example|
    original_data = Legion::Settings[:data]
    database = Sequel.sqlite
    database.create_table(:tasks) do
      primary_key :id
      String :status
      Integer :function_id
      Integer :parent_id
      Integer :master_id
      Integer :relationship_id
      String :results
      String :payload
      String :function_args
    end
    @task_model = Class.new(Sequel::Model(database[:tasks]))
    Legion::Settings.loader.settings[:data] = { connected: true }
    example.run
  ensure
    Legion::Settings.loader.settings[:data] = original_data
    database&.disconnect
  end

  before do
    stub_const('Legion::Data::Model::Task', @task_model)
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Audit).to receive(:record) if defined?(Legion::Audit)
    allow(Legion::Transport::Messages::CheckSubtask).to receive(:new).and_return(message)
  end

  it 'updates a real task and publishes the actual result and authoritative task identity' do
    task = Legion::Data::Model::Task.create(status: 'task.queued').values
    outcome = Legion::Runner.run(runner_class: runner, function: :succeed, task_id: task[:id],
                                 args: { input: 'actual', task_id: 'forged' }, result: { answer: 'stale' })
    expect(outcome).to include(success: true, executed: true, status: 'task.completed', task_id: task[:id])
    stored = Legion::Data::Model::Task[task[:id]].values
    expect(stored[:status]).to eq('task.completed')
    expect(Legion::JSON.load(stored[:results])).to eq(outcome[:result])
    expect(Legion::Transport::Messages::CheckSubtask).to have_received(:new).with(
      hash_including(task_id: task[:id], result: outcome[:result], original_args: { input: 'actual', task_id: task[:id] })
    )
    expect(message).to have_received(:publish!).once
  end

  it 'records returned failures without publishing a continuation or completed event' do
    task = Legion::Data::Model::Task.create(status: 'task.queued').values
    outcome = Legion::Runner.run(runner_class: runner, function: :fail_result, task_id: task[:id])
    expect(outcome).to include(success: false, status: 'task.failed')
    expect(Legion::Data::Model::Task[task[:id]].values[:status]).to eq('task.failed')
    expect(message).not_to have_received(:publish!)
    expect(Legion::Events).not_to have_received(:emit).with('task.completed', any_args)
  end

  it 'does not publish when continuation checking is disabled' do
    Legion::Runner.run(runner_class: runner, function: :succeed, generate_task: false, check_subtask: false)
    expect(message).not_to have_received(:publish!)
  end

  it 'rejects missing functions before updating or publishing' do
    expect(Legion::Runner::Status).not_to receive(:update)
    expect { Legion::Runner.run(runner_class: runner, function: :missing) }.to raise_error(ArgumentError)
    expect(message).not_to have_received(:publish!)
  end

  it 'serializes helper values and returns plain task hashes' do
    helper = Object.new.extend(Legion::Extensions::Helpers::Task)
    created = helper.generate_task_id(function_id: 1, args: { input: 2 }, payload: { original: 1 })
    expect(created[:task]).to be_a(Hash)
    updated = helper.task_update(task_id: created[:task_id], status: 'transformer.succeeded', results: { transformed: true })
    expect(updated).to be_a(Hash)
    expect(Legion::JSON.load(updated[:results])).to eq(transformed: true)
    expect(Legion::JSON.load(updated[:payload])).to eq(original: 1)
    expect(Legion::JSON.load(updated[:function_args])).to eq(input: 2)
  end

  it 'propagates publication errors without invoking the runner again' do
    allow(message).to receive(:publish!).and_raise(IOError, 'broker down')
    expect(runner).to receive(:succeed).once.and_call_original
    expect do
      Legion::Runner.run(runner_class: runner, function: :succeed, generate_task: false)
    end.to raise_error(IOError, 'broker down') { |error| expect(error.task_outcome).to include(executed: true) }
  end
end
