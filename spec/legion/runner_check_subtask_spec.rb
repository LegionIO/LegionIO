# frozen_string_literal: true

require 'spec_helper'
require 'legion/data'
require 'legion/runner'
require 'legion/extensions/helpers/task'
require 'tmpdir'
require 'fileutils'
require 'sequel/extensions/migration'
require 'timeout'

module PersistedTaskRunner
  class << self
    attr_accessor :calls

    def succeed(**args)
      self.calls += 1
      { success: true, answer: args[:input], received_task_id: args[:task_id] }
    end

    def returned_failure(**)
      self.calls += 1
      { success: false, status: 'task.completed', error: 'business rejection' }
    end

    def raise_after_effect(**)
      self.calls += 1
      raise IOError, 'remote outcome unknown'
    end

    def wait_for_release(started:, release:, **)
      self.calls += 1
      started << true
      release.pop
      { success: true }
    end
  end
end

RSpec.describe 'Runner durable completion boundary' do
  include Legion::Settings::TaskExecution::Helper

  before(:context) do
    @directory = Dir.mktmpdir('legion-core-tasks')
    @database = Sequel.sqlite(File.join(@directory, 'tasks.db'))
    Sequel::Migrator.run(@database, File.join(Gem.loaded_specs.fetch('legion-data').full_gem_path, 'lib/legion/data/migrations'))
  end

  after(:context) do
    @database&.disconnect
    FileUtils.remove_entry(@directory) if @directory
  end

  around do |example|
    Legion::Runner.task_execution_settings
    original_db = Legion::Data::Connection.instance_variable_get(:@sequel)
    original_data = Legion::Settings[:data]
    original_client = Legion::Settings[:client]
    original_tasks = Legion::Settings[:task_execution]
    Legion::Settings.loader.settings[:task_execution] = Legion::Settings::TaskExecution.default
    original_listeners = Legion::Events.instance_variable_get(:@listeners)
    Legion::Data::Connection.instance_variable_set(:@sequel, @database)
    Legion::Settings.loader.settings[:data] = { connected: true }
    Legion::Settings.loader.settings[:client] = { name: 'core-spec' }
    Legion::Events.instance_variable_set(:@listeners, Hash.new { |hash, key| hash[key] = [] })
    @database[:task_dispatches].delete
    @database[:task_attempts].delete
    @database[:tasks].delete
    PersistedTaskRunner.calls = 0
    example.run
  ensure
    Legion::Data::Connection.instance_variable_set(:@sequel, original_db)
    Legion::Settings.loader.settings[:data] = original_data
    Legion::Settings.loader.settings[:client] = original_client
    Legion::Settings.loader.settings[:task_execution] = original_tasks
    Legion::Events.instance_variable_set(:@listeners, original_listeners)
  end

  def create_task(**values)
    Legion::Data::TaskExecution.create_task(values: values, idempotency_key: SecureRandom.uuid).fetch(:task)
  end

  it 'records one completion and continuation despite redelivery, without stale payload overriding results or identity' do
    master = create_task
    task = create_task(master_id: master[:id])
    events = []
    Legion::Events.on(task_status(name: :completed)) { |event| events << event }
    first = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :succeed, task_id: task[:id],
                               master_id: 'stale-master', args: { input: 'actual', task_id: 'forged' }, result: { answer: 'stale' })
    second = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :succeed, task_id: task[:id])
    expect(first).to include(success: true, persisted: true, status: task_status(name: :completed))
    expect(second).to include(success: true, executed: false, result: first[:result])
    expect(PersistedTaskRunner.calls).to eq(1)
    expect(events.size).to eq(1)
    expect(@database[:task_attempts].count).to eq(1)
    dispatches = Legion::Data::TaskExecution.claim_dispatches(owner: 'relay')
    expect(dispatches.size).to eq(1)
    expect(dispatches.first[:options]).to include(task_id: task[:id], master_id: master[:id],
                                                  result: { success: true, answer: 'actual', received_task_id: task[:id] })
    late_failure = Legion::Runner::Status.update(task_id: task[:id], status: task_status(name: :failed), results: { error: 'late' })
    expect(late_failure[:changed]).to be false
    expect(@database[:tasks].where(id: task[:id]).get(:status)).to eq(task_status(name: :completed))
  end

  it 'persists returned failure without completion, continuation, or success learning events' do
    task = create_task
    completed = []
    Legion::Events.on(task_status(name: :completed)) { |event| completed << event }
    outcome = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :returned_failure, task_id: task[:id])
    expect(outcome).to include(success: false, status: task_status(name: :failed))
    expect(@database[:tasks].where(id: task[:id]).get(:status)).to eq(task_status(name: :failed))
    expect(@database[:task_dispatches].count).to eq(0)
    expect(completed).to be_empty
  end

  it 're-raises the original exception after recording unknown effects and refuses redelivery' do
    task = create_task
    expect do
      Legion::Runner.run(runner_class: PersistedTaskRunner, function: :raise_after_effect, task_id: task[:id])
    end.to raise_error(IOError, 'remote outcome unknown') { |error| expect(error.task_outcome[:status]).to eq(task_status(name: :unknown)) }
    replay = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :raise_after_effect, task_id: task[:id])
    expect(replay).to include(success: false, executed: false, status: task_status(name: :unknown))
    expect(PersistedTaskRunner.calls).to eq(1)
    expect(@database[:task_dispatches].count).to eq(0)
  end

  it 'permits only explicitly safe retry attempts and exhausts the total attempt budget' do
    task = create_task
    Legion::Settings[:task_execution][:retry].merge!(safe_runners: { 'PersistedTaskRunner#raise_after_effect' => true },
                                                     max_attempts: 2)
    first = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :raise_after_effect, task_id: task[:id], catch_exceptions: true)
    expect(first[:status]).to eq(task_status(name: :retry_pending))
    @database[:tasks].where(id: task[:id]).update(retry_at: Time.now - 1)
    second = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :raise_after_effect, task_id: task[:id], catch_exceptions: true)
    expect(second[:status]).to eq(task_status(name: :exception))
    expect(PersistedTaskRunner.calls).to eq(2)
    expect(@database[:task_attempts].count).to eq(2)
  end

  it 'does not execute expired or cancelled tasks' do
    expired = create_task(deadline_at: Time.now - 1)
    cancelled = create_task(cancelled_at: Time.now)
    expired_result = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :succeed, task_id: expired[:id])
    cancelled_result = Legion::Runner.run(runner_class: PersistedTaskRunner, function: :succeed, task_id: cancelled[:id])
    expect(expired_result[:status]).to eq(task_status(name: :expired))
    expect(cancelled_result[:status]).to eq(task_status(name: :cancelled))
    expect(PersistedTaskRunner.calls).to eq(0)
  end

  it 'validates missing functions before an attempt or success event can exist' do
    task = create_task
    expect do
      Legion::Runner.run(runner_class: PersistedTaskRunner, function: :does_not_exist, task_id: task[:id])
    end.to raise_error(ArgumentError)
    expect(@database[:task_attempts].count).to eq(0)
    expect(@database[:task_dispatches].count).to eq(0)
  end

  it 'renews a live long-running attempt and stops its heartbeat before completion' do
    task = create_task
    Legion::Settings[:task_execution][:execution].merge!(heartbeat_seconds: 1, lease_seconds: 3)
    started = Queue.new
    release = Queue.new
    invocation = Thread.new do
      Legion::Runner.run(runner_class: PersistedTaskRunner, function: :wait_for_release, task_id: task[:id],
                         args: { started: started, release: release }, check_subtask: false)
    end
    Timeout.timeout(5) { started.pop }
    original_lease = @database[:tasks].where(id: task[:id]).get(:execution_lease_until)
    Timeout.timeout(3) do
      sleep(0.02) until @database[:tasks].where(id: task[:id]).get(:execution_lease_until) > original_lease
    end
    competitor = Legion::Data::TaskExecution.claim_task(task_id: task[:id], owner: 'competitor', now: original_lease + 0.1)
    expect(competitor[:claimed]).to be false
    release << true
    expect(invocation.value).to include(success: true, status: task_status(name: :completed))
    expect(@database[:tasks].where(id: task[:id]).get(:execution_lease_until)).to be_nil
  ensure
    release << true if release && invocation&.alive?
    invocation&.join
  end

  it 'persists helper results, payload, and arguments rather than only the status' do
    task = create_task
    helper = Object.new.extend(Legion::Extensions::Helpers::Task)
    outcome = helper.task_update(task_id: task[:id], status: task_status(name: :transformer_succeeded),
                                 results: { transformed: true }, payload: { original: 1 }, function_args: { input: 2 })
    stored = @database[:tasks].where(id: task[:id]).first
    expect(outcome[:changed]).to be true
    expect(Legion::JSON.load(stored[:results])).to eq(transformed: true)
    expect(Legion::JSON.load(stored[:payload])).to eq(original: 1)
    expect(Legion::JSON.load(stored[:function_args])).to eq(input: 2)
  end
end
