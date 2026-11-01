# frozen_string_literal: true

require_relative 'base'
require_relative 'logger'
require 'legion/transport'
require 'legion/transport/messages/task_update'
require 'legion/transport/messages/task_log'
require 'legion/transport/task_protocol'
require 'legion/data/task_execution'
require 'securerandom'

module Legion
  module Extensions
    module Helpers
      module Task
        include Legion::Extensions::Helpers::Base
        include Legion::Extensions::Helpers::Logger
        include Legion::Transport::TaskProtocol::Helper

        def generate_task_log(task_id:, function:, runner_class: to_s, **payload)
          begin
            if Legion::Settings[:data][:connected]
              runner_id = Legion::Data::Model::Runner[namespace: runner_class].values[:id]
              function_id = Legion::Data::Model::Function.where(runner_id: runner_id, name: function).first.values[:id]
              return true if Legion::Data::Model::TaskLog.insert(task_id: task_id, function_id: function_id, entry: Legion::JSON.dump(payload))
            end
          rescue StandardError => e
            handle_exception(e, level: :warn)
          end
          Legion::Transport::Messages::TaskLog.new(task_id: task_id, runner_class: runner_class, function: function, entry: payload).publish
        end

        def task_update(task_id:, status:, use_database: true, expected_status: nil, token: nil, **opts) # rubocop:disable Metrics/ParameterLists
          raise ArgumentError, 'task_id and status are required' if task_id.nil? || status.nil?

          values = opts.slice(:results, :payload, :function_args)
          if Legion::Settings[:data].is_a?(Hash) && Legion::Settings[:data][:connected] && use_database
            return Legion::Data::TaskExecution.transition_task(task_id: task_id, status: status, expected_status: expected_status,
                                                               token: token, values: values)
          end

          Legion::Transport::Messages::TaskUpdate.new(**values, task_id: task_id, status: status,
                                                                expected_status: expected_status, token: token).publish!
        rescue StandardError => e
          handle_exception(e, level: :error)
          raise
        end

        def generate_task_id(function_id:, status: nil, **opts)
          values = opts.slice(:master_id, :parent_id, :relationship_id, :deadline_at).compact
          values.merge!(status: status || task_status(name: :queued), function_id: function_id)
          values[:payload] = opts[:payload] if opts.key?(:payload)
          values[:function_args] = opts[:args] if opts.key?(:args)
          key = opts[:idempotency_key] || opts[:message_id] || SecureRandom.uuid
          created = Legion::Data::TaskExecution.create_task(values: values, idempotency_key: "helper:#{key}")
          { success: true, task_id: created[:task][:id], **created }
        end
      end
    end
  end
end
