# frozen_string_literal: true

require 'bundler/setup'
require 'legion'
require 'legion/extensions'
require 'legion/ingress'
require 'legion/rbac'
require 'legion/data'
require 'legion/transport'
require 'sequel/extensions/migration'
require 'tmpdir'
require 'uri'

Legion::Logging.setup(level: 'fatal', log_file: File::NULL, log_stdout: false, async: false)
Legion::Settings[:rbac][:enabled] = false
Legion::Settings[:transport][:messages][:encrypt] = false
Legion::Settings[:transport][:task_publication][:spool] = false
uri = URI(ENV.fetch('RABBITMQ_URL'))
Legion::Settings[:transport][:connection].merge!(host: uri.host, port: uri.port, user: uri.user, password: uri.password,
                                                 vhost: URI.decode_www_form_component(uri.path.delete_prefix('/')))
Legion::Settings[:transport][:resolved_hosts] = []
Legion::Settings[:transport][:connection_pool_size] = 1
Legion::Transport::Connection.setup

reports = []
Dir.mktmpdir('legion-pipeline-contract') do |directory|
  database = Sequel.sqlite(File.join(directory, 'pipeline.db'))
  Legion::Data::Connection.sequel = database
  Legion::Settings[:data][:connected] = true
  Sequel::Model.db = database
  Sequel::Migrator.run(database, File.join(Gem.loaded_specs.fetch('legion-data').full_gem_path, 'lib/legion/data/migrations'))
  %w[extension runner function relationship task task_log node].each { |model| require "legion/data/models/#{model}" }
  database.create_table(:pipeline_effects) do
    primary_key :id
    Integer :task_id, null: false, unique: true
    Integer :value, null: false
  end

  %w[tasker conditioner transformer].each { |name| require "legion/extensions/#{name}" }
  [Legion::Extensions::Tasker, Legion::Extensions::Conditioner, Legion::Extensions::Transformer].each do |extension|
    extension.extend(Legion::Extensions::Core)
    extension.build_settings
    extension.build_runners
  end
  require 'legion/extensions/tasker/actors/check_subtask'
  require 'legion/extensions/conditioner/actors/conditioner'
  require 'legion/extensions/transformer/actors/transform'

  module Legion
    module Extensions
      module CanonicalPipeline
        module Runners
          module Source
            def self.produce(value:, **)
              { success: true, value: value }
            end
          end

          module Destination
            %i[consume first second].each do |name|
              define_singleton_method(name) do |value:, task_id:, **|
                Legion::Data.connection[:pipeline_effects].insert(task_id: task_id, value: value)
                { success: true, value: value }
              end
            end
          end
        end

        module Actor
          class Destination < Legion::Extensions::Actors::Subscription
            def find_function(message = {})
              message.fetch(:function)
            end
          end
        end
      end
    end
  end

  channel = Legion::Transport::Connection.channel
  task_exchange = Legion::Transport::Exchanges::Task.new
  stages = {
    'task.subtask.check'       => Legion::Extensions::Tasker::Actor::CheckSubtask,
    'task.subtask.conditioner' => Legion::Extensions::Conditioner::Actor::Conditioner,
    'task.subtask.transform'   => Legion::Extensions::Transformer::Actor::Transform
  }
  consumers = stages.map do |route, actor_class|
    queue = Legion::Transport::Queue.new("canonical-stage-#{SecureRandom.hex(6)}", channel: channel, durable: false, exclusive: true, auto_delete: true,
                                        arguments: { 'x-queue-type': 'classic', 'x-dead-letter-exchange': nil })
    queue.bind(task_exchange, routing_key: route)
    actor = actor_class.allocate
    actor.instance_variable_set(:@queue, queue)
    [queue, actor]
  end
  stage_events = []
  Legion::Events.on('task.completed') do |event|
    stage_events << event if event[:runner_class] == 'Legion::Extensions::Conditioner::Runners::Conditioner'
  end

  cases = [
    { name: 'one-to-one', targets: %w[consume], transformation: '{"value":42}' },
    { name: 'relationship fan-out', targets: %w[first second], transformation: '{"value":43}' },
    { name: 'transformation fan-out', targets: %w[consume], transformation: '[{"value":44},{"value":45}]' },
    { name: 'condition rejection', targets: %w[consume], transformation: '{"value":99}', condition_value: 0 }
  ]
  source_extension = Legion::Data::Model::Extension.create(name: 'canonical-source', namespace: 'CanonicalPipeline', exchange: 'canonical-source')
  source = Legion::Data::Model::Runner.create(extension_id: source_extension.id, name: 'source', queue: 'source', namespace: 'Legion::Extensions::CanonicalPipeline::Runners::Source')
  trigger = Legion::Data::Model::Function.create(runner_id: source.id, name: 'produce')
  cases.each do |scenario|
    database[:pipeline_effects].delete
    database[:relationships].where(trigger_id: trigger.id).update(active: false)
    stage_events.clear
    exchange_name = "canonical.#{SecureRandom.hex(6)}"
    extension = Legion::Data::Model::Extension.create(name: exchange_name, namespace: 'CanonicalPipeline', exchange: exchange_name)
    destination = Legion::Data::Model::Runner.create(extension_id: extension.id, name: 'destination', queue: 'destination', namespace: 'Legion::Extensions::CanonicalPipeline::Runners::Destination')
    destination_exchange = Legion::Transport::Exchange.new(exchange_name)
    destination_queue = Legion::Transport::Queue.new("canonical-destination-#{SecureRandom.hex(6)}", channel: channel, durable: false,
                                                    exclusive: true, auto_delete: true,
                                                    arguments: { 'x-queue-type': 'classic', 'x-dead-letter-exchange': nil })
    destination_queue.bind(destination_exchange, routing_key: "#{exchange_name}.destination.*")
    destination_actor = Legion::Extensions::CanonicalPipeline::Actor::Destination.allocate
    destination_actor.instance_variable_set(:@queue, destination_queue)
    scenario[:targets].each do |function|
      action = Legion::Data::Model::Function.create(runner_id: destination.id, name: function)
      conditions = { all: [{ fact: 'args.value', operator: 'equal', value: scenario.fetch(:condition_value, 41) }] }
      Legion::Data::Model::Relationship.create(trigger_id: trigger.id, action_id: action.id, allow_new_chains: true,
                                               conditions: Legion::JSON.dump(conditions),
                                               transformation: scenario[:transformation], engine: 'static')
    end
    root = Legion::Data::TaskExecution.create_task(values:          { function_id: trigger.id, function_args: { value: 41 } },
                                                   idempotency_key: SecureRandom.uuid).fetch(:task)
    result = Legion::Ingress.run(payload: { task_id: root[:id], args: { value: 41 } },
                                 runner_class: Legion::Extensions::CanonicalPipeline::Runners::Source, function: 'produce', source: 'pipeline-smoke')
    raise "root execution failed: #{result.inspect}" unless result[:success]

    active = consumers + [[destination_queue, destination_actor]]
    deadline = Time.now + 10
    loop do
      dispatch = Legion::Extensions::Tasker::Runners::Outbox.dispatch_pending
      raise "outbox rejected work: #{dispatch.inspect}" unless dispatch[:success]

      delivered = 0
      active.each do |queue, actor|
        loop do
          info, metadata, payload = queue.pop(manual_ack: true)
          break unless payload

          raise 'pipeline delivery kept failing or requeuing' if Time.now >= deadline

          actor.send(:handle_delivery, delivery_info: info, metadata: metadata, payload: payload)
          delivered += 1
        end
      end
      pending = database[:task_dispatches].where(delivered_at: nil, discarded_at: nil).count
      break if delivered.zero? && pending.zero?
      raise 'pipeline failed to settle' if Time.now >= deadline
    end

    reports << {
      name: scenario[:name], root: database[:tasks].where(id: root[:id]).first.slice(:id, :status),
      effects: database[:pipeline_effects].all.map { |row| row.slice(:task_id, :value) },
      tasks: database[:tasks].where(master_id: root[:id]).all.map do |row|
        row.slice(:id, :parent_id, :master_id, :status, :attempt_count)
      end,
      conditioner_completions: stage_events.length
    }
    destination_queue.delete
    destination_exchange.delete
  end
ensure
  database&.disconnect
  Legion::Transport::Connection.shutdown
end

File.write(ARGV.fetch(0), Legion::JSON.dump(reports))
