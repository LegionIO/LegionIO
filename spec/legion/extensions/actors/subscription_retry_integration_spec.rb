# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner'
require 'legion/extensions/actors/subscription'
require 'legion/rbac'
require 'legion/data'
require 'tmpdir'
require 'fileutils'
require 'sequel/extensions/migration'

module TaskExecutionBoundary
  module Runner
    class << self
      attr_accessor :calls

      def succeed(**)
        self.calls += 1
        { success: true, context: Legion::Context.current_task_context }
      end

      def raise_once(**)
        self.calls += 1
        raise IOError, 'temporary failure before effect' if calls == 1

        { success: true, result: 'finished' }
      end

      def fail_result(**)
        self.calls += 1
        { success: false, error: 'rejected' }
      end

      def unknown_effect(**)
        self.calls += 1
        raise IOError, 'connection lost after external effect'
      end
    end
  end

  class Consumer < Legion::Extensions::Actors::Subscription
    def runner_class = TaskExecutionBoundary::Runner
    def lex_name = 'task_execution_boundary'
    def runner_name = 'runner'
    def find_function(message = {}) = message.fetch(:function)
    def check_subtask? = false
    def generate_task? = false
  end

  class InternalConsumer < Consumer
    trusted_internal true
  end

  module Stage
    class << self
      attr_accessor :forwarded

      def forward(runner_class:, function:, args:, **metadata)
        self.forwarded = metadata.merge(runner_class: runner_class, function: function, args: args)
        { success: true }
      end
    end
  end

  class StageConsumer < Consumer
    trusted_internal true
    def runner_class = TaskExecutionBoundary::Stage
    def find_function(_message = {}) = :forward
    def use_runner? = false
  end

  class Queue
    attr_reader :settlements

    def initialize
      @settlements = []
    end

    def name = 'task-execution-boundary'
    def channel = self
    def default_exchange = self
    def acknowledge(tag) = settlements.push([:ack, tag])
    def reject(tag, requeue:) = settlements.push([:reject, tag, requeue])
  end
end

RSpec.describe 'Subscription execution recovery boundary' do
  let(:queue) { TaskExecutionBoundary::Queue.new }
  let(:consumer) { TaskExecutionBoundary::Consumer.allocate }
  let(:delivery) { Struct.new(:delivery_tag, :routing_key).new('delivery-1', 'runner.work') }
  let(:metadata) do
    Struct.new(:headers, :content_type, :content_encoding, :message_id, :correlation_id, :reply_to)
          .new({ 'tenant_id' => 'tenant-a' }, 'application/json', nil, 'message-1', 'chain-1', 'reply-queue')
  end

  around do |example|
    Legion::Runner.task_execution_settings
    original_tasks = Legion::Settings[:task_execution]
    Legion::Settings.loader.settings[:task_execution] = Legion::TaskExecution::Settings.default
    original_data = Legion::Settings[:data]
    original_client = Legion::Settings[:client]
    original_listeners = Legion::Events.instance_variable_get(:@listeners)
    original_rbac = Legion::Settings[:rbac]
    original_roles = Legion::Rbac.instance_variable_get(:@role_index)
    Legion::Settings.loader.settings[:rbac] = { enabled: false }
    Legion::Settings.loader.settings[:data] = { connected: false }
    Legion::Settings.loader.settings[:client] = { shutting_down: false }
    Legion::Settings[:task_execution][:retry][:safe_runners] = { 'TaskExecutionBoundary::Runner#raise_once' => true }
    Legion::Events.instance_variable_set(:@listeners, Hash.new { |hash, key| hash[key] = [] })
    example.run
  ensure
    Legion::Settings.loader.settings[:task_execution] = original_tasks
    Legion::Settings.loader.settings[:data] = original_data
    Legion::Settings.loader.settings[:client] = original_client
    Legion::Events.instance_variable_set(:@listeners, original_listeners)
    Legion::Settings.loader.settings[:rbac] = original_rbac
    Legion::Rbac.instance_variable_set(:@role_index, original_roles)
  end

  before do
    TaskExecutionBoundary::Runner.calls = 0
    consumer.instance_variable_set(:@queue, queue)
    allow(consumer).to receive(:sleep)
  end

  def deliver(function:, metadata: self.metadata, **fields)
    consumer.send(:handle_delivery, delivery_info: delivery, metadata: metadata,
                                   payload: Legion::JSON.dump({ function: function, args: { value: 'business' }, **fields }))
  end

  it 'reaches recovery from a real raising runner and acknowledges only a confirmed retry with its envelope' do
    published = nil
    allow(Legion::Transport::Publisher).to receive(:publish!) do |**options|
      expect(queue.settlements).to be_empty
      published = options
      { accepted: true }
    end
    deliver(function: 'raise_once')
    expect(TaskExecutionBoundary::Runner.calls).to eq(1)
    expect(queue.settlements).to eq([[:ack, 'delivery-1']])
    expect(published[:envelope]).to include(message_id: 'message-1', correlation_id: 'chain-1', reply_to: 'reply-queue',
                                            headers: { 'tenant_id' => 'tenant-a', 'x-retry-count' => 1 })
    expect(Legion::JSON.load(published[:payload])).to include(args: { value: 'business' })

    metadata.headers = published[:envelope][:headers]
    deliver(function: 'raise_once')
    expect(TaskExecutionBoundary::Runner.calls).to eq(2)
    expect(queue.settlements).to eq([[:ack, 'delivery-1'], [:ack, 'delivery-1']])
  end

  it 'retains the original delivery when confirmed retry publication is rejected' do
    allow(Legion::Transport::Publisher).to receive(:publish!).and_raise(IOError, 'broker unavailable')
    deliver(function: 'raise_once')
    expect(queue.settlements).to eq([[:reject, 'delivery-1', true]])
  end

  it 'does not retry ambiguous effects when a present safe-runner grant is explicitly false' do
    Legion::Settings[:task_execution][:retry][:safe_runners]['TaskExecutionBoundary::Runner#unknown_effect'] = false
    expect(Legion::Transport::Publisher).not_to receive(:publish!)
    deliver(function: 'unknown_effect')
    expect(TaskExecutionBoundary::Runner.calls).to eq(1)
    expect(queue.settlements).to eq([[:reject, 'delivery-1', false]])
  end

  it 'ignores inbound policy when applying the ephemeral retry limit' do
    Legion::Settings[:task_execution][:retry][:max_attempts] = 1
    expect(Legion::Transport::Publisher).not_to receive(:publish!)
    deliver(function: 'raise_once', execution_policy: { retry: { max_attempts: 99 } })
    expect(queue.settlements).to eq([[:reject, 'delivery-1', false]])
  end

  context 'with durable task policy' do
    before(:context) do
      @directory = Dir.mktmpdir('legion-subscription-tasks')
      @database = Sequel.sqlite(File.join(@directory, 'tasks.db'))
      Sequel::Migrator.run(@database, File.join(Gem.loaded_specs.fetch('legion-data').full_gem_path, 'lib/legion/data/migrations'))
    end

    after(:context) do
      @database&.disconnect
      FileUtils.remove_entry(@directory) if @directory
    end

    around do |example|
      original_db = Legion::Data::Connection.instance_variable_get(:@sequel)
      Legion::Data::Connection.instance_variable_set(:@sequel, @database)
      Legion::Settings.loader.settings[:data] = Legion::Data::Settings.default.merge(connected: true)
      Legion::Settings[:client][:name] = 'subscription-spec'
      example.run
    ensure
      Legion::Data::Connection.instance_variable_set(:@sequel, original_db)
    end

    it 'retains a durable retry beyond local thresholds, waits for persisted retry_at, and executes after redelivery' do
      Legion::Settings[:data][:task_execution][:retry].merge!(max_attempts: 3, base_delay_seconds: 4, max_delay_seconds: 4)
      task = Legion::Data::TaskExecution.create_task(values: {}, idempotency_key: SecureRandom.uuid).fetch(:task)
      Legion::Settings[:data][:task_execution][:retry].merge!(max_attempts: 1, base_delay_seconds: 1, max_delay_seconds: 1)
      Legion::Settings[:task_execution][:retry].merge!(max_attempts: 1, base_delay_seconds: 1, max_delay_seconds: 1)
      metadata.headers['x-retry-count'] = 9
      published = nil
      allow(Legion::Transport::Publisher).to receive(:publish!) do |**options|
        expect(queue.settlements).to be_empty
        published = options
        { accepted: true }
      end
      expect(consumer).to receive(:sleep).with(be_within(1).of(4))
      deliver(function: 'raise_once', task_id: task[:id])
      expect(@database[:tasks].where(id: task[:id]).get(:status)).to eq('task.retry_pending')
      expect(queue.settlements).to eq([[:ack, 'delivery-1']])
      expect(published[:envelope]).to include(message_id: 'message-1', correlation_id: 'chain-1',
                                              headers: { 'tenant_id' => 'tenant-a', 'x-retry-count' => 10 })
      expect(Legion::JSON.load(published[:payload])).to include(task_id: task[:id], args: { value: 'business' })

      metadata.headers = published[:envelope][:headers]
      deliver(function: 'raise_once', task_id: task[:id])
      expect(TaskExecutionBoundary::Runner.calls).to eq(1)
      expect(queue.settlements.last).to eq([:reject, 'delivery-1', true])
      @database[:tasks].where(id: task[:id]).update(retry_at: Time.now - 1)
      deliver(function: 'raise_once', task_id: task[:id])
      expect(TaskExecutionBoundary::Runner.calls).to eq(2)
      expect(queue.settlements.last).to eq([:ack, 'delivery-1'])
      expect(@database[:tasks].where(id: task[:id]).get(:status)).to eq('task.completed')
    end
  end

  it 'does not emit completion or publish continuation for a returned failure' do
    completed = []
    Legion::Events.on('task.completed') { |event| completed << event }
    expect(Legion::Transport::Messages::CheckSubtask).not_to receive(:new)
    expect(Legion::Transport::Publisher).not_to receive(:publish!)
    deliver(function: 'fail_result')
    expect(completed).to be_empty
    expect(queue.settlements).to eq([[:reject, 'delivery-1', false]])
  end

  it 'defers quiescing work without running or acknowledging it' do
    allow(Legion::Extensions).to receive(:dispatch_allowed?).with('task_execution_boundary').and_return(false)
    deliver(function: 'raise_once')
    expect(TaskExecutionBoundary::Runner.calls).to eq(0)
    expect(queue.settlements).to eq([[:reject, 'delivery-1', true]])
  end

  context 'with authorization enabled' do
    before do
      Legion::Settings.loader.settings[:rbac] = Legion::Rbac::Settings.default.merge(
        static_assignments: [{ principal_id: 'privileged-user', principal_type: 'human', role: 'admin' }]
      )
      Legion::Rbac.setup
    end

    it 'executes an explicitly authenticated local caller without trusting payload identity' do
      principal = Legion::Rbac::Principal.new(id: 'authenticated-local', roles: ['worker'])
      result = Legion::Ingress.run(payload: { principal_id: 'forged' }, runner_class: TaskExecutionBoundary::Runner,
                                   function: :succeed, source: 'cli', principal: principal, generate_task: false, check_subtask: false)
      expect(result[:success]).to be true
      expect(TaskExecutionBoundary::Runner.calls).to eq(1)
    end

    it 'ignores a forged AMQP identity even when the real store assigns that identity admin privileges' do
      expect(Legion::Rbac::Store.roles_for(principal_id: 'privileged-user', principal_type: 'human')).to include('admin')
      metadata.headers.merge!('principal_id' => 'privileged-user', 'principal_type' => 'human', 'source' => 'cli', 'roles' => ['admin'])
      deliver(function: 'succeed')
      expect(TaskExecutionBoundary::Runner.calls).to eq(0)
      expect(queue.settlements).to eq([[:reject, 'delivery-1', false]])
    end

    it 'authorizes the server-owned service subject, retaining a claimed user only as audit origin' do
      internal = TaskExecutionBoundary::InternalConsumer.allocate
      internal.instance_variable_set(:@queue, queue)
      outcomes = []
      Legion::Events.on('task.completed') { |event| outcomes << event }
      metadata.headers.merge!('principal_id' => 'privileged-user', 'principal_type' => 'human')
      internal.send(:handle_delivery, delivery_info: delivery, metadata: metadata,
                                      payload: Legion::JSON.dump({ function: 'succeed', args: {} }))
      expect(TaskExecutionBoundary::Runner.calls).to eq(1)
      expect(queue.settlements).to eq([[:ack, 'delivery-1']])
      expect(outcomes.first[:result][:context]).to include(principal_id: 'legion-task-service', principal_type: :worker,
                                                           originating_principal_id: 'privileged-user', originating_principal_type: 'human')
    end

    it 'denies a trusted service actor when its configured worker role is revoked' do
      Legion::Settings[:task_execution][:ingress][:trusted_internal_principal][:roles][:worker] = false
      internal = TaskExecutionBoundary::InternalConsumer.allocate
      internal.instance_variable_set(:@queue, queue)
      internal.send(:handle_delivery, delivery_info: delivery, metadata: metadata,
                                      payload: Legion::JSON.dump({ function: 'succeed', args: {} }))
      expect(TaskExecutionBoundary::Runner.calls).to eq(0)
      expect(queue.settlements).to eq([[:reject, 'delivery-1', false]])
    end

    it 'preserves the eventual target, lineage, and business args through an admitted orchestration stage' do
      stage = TaskExecutionBoundary::StageConsumer.allocate
      stage.instance_variable_set(:@queue, queue)
      internal = TaskExecutionBoundary::InternalConsumer.allocate
      internal.instance_variable_set(:@queue, queue)
      envelope = { runner_class: 'TaskExecutionBoundary::Runner', function: 'succeed', args: { input: 'scheduled' },
                   principal_id: 'claimed-origin', principal_type: 'human', parent_id: 7, schedule_id: 12, occurrence_id: 'occurrence-1' }
      stage.send(:handle_delivery, delivery_info: delivery, metadata: metadata, payload: Legion::JSON.dump(envelope))
      expect(TaskExecutionBoundary::Runner.calls).to eq(0)
      expect(TaskExecutionBoundary::Stage.forwarded).to include(runner_class: 'TaskExecutionBoundary::Runner', function: 'succeed',
                                                                args: { input: 'scheduled' }, parent_id: 7, schedule_id: 12,
                                                                occurrence_id: 'occurrence-1', originating_principal_id: 'claimed-origin')
      internal.send(:handle_delivery, delivery_info: delivery, metadata: metadata,
                                      payload: Legion::JSON.dump(TaskExecutionBoundary::Stage.forwarded))
      expect(TaskExecutionBoundary::Runner.calls).to eq(1)
      expect(queue.settlements).to eq([[:ack, 'delivery-1'], [:ack, 'delivery-1']])
    end
  end
end
