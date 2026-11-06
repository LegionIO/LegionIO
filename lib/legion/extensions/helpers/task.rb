# frozen_string_literal: true

require_relative 'base'
require_relative 'logger'
require 'legion/transport'
require 'legion/transport/messages/task_update'
require 'legion/transport/messages/task_log'
require 'legion/transport/task/protocol'

module Legion
  module Extensions
    module Helpers
      module Task
        include Legion::Extensions::Helpers::Base
        include Legion::Extensions::Helpers::Logger
        include Legion::Transport::Task::Protocol::Helper

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

        def task_update(task_id:, status:, use_database: true, **opts)
          raise ArgumentError, 'task_id and status are required' if task_id.nil? || status.nil?

          values = opts.slice(:results, :payload, :function_args)
          if Legion::Settings[:data].is_a?(Hash) && Legion::Settings[:data][:connected] && use_database
            values.transform_values! { |value| value.is_a?(Hash) ? Legion::JSON.dump(value) : value }
            return Legion::Data::Model::Task[task_id].update(values.merge(status: status)).values
          end

          Legion::Transport::Messages::TaskUpdate.new(**values, task_id: task_id, status: status).publish!
        rescue StandardError => e
          handle_exception(e, level: :error)
          raise
        end

        def generate_task_id(function_id:, status: nil, **opts)
          values = opts.slice(:master_id, :parent_id, :relationship_id).compact
          values.merge!(status: status || task_status(name: :queued), function_id: function_id)
          values[:payload] = opts[:payload] if opts.key?(:payload)
          values[:function_args] = opts[:args] if opts.key?(:args)
          values.transform_values! { |value| value.is_a?(Hash) ? Legion::JSON.dump(value) : value }
          task = Legion::Data::Model::Task.create(values).values
          { success: true, task_id: task[:id], task: task }
        end
      end
    end
  end
end
