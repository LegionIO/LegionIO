# frozen_string_literal: true

require_relative 'base'
require 'legion/transport'
require 'legion/transport/messages/task_update'
require 'legion/transport/messages/task_log'

module Legion
  module Extensions
    module Helpers
      module Task
        include Legion::Extensions::Helpers::Base

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

        def task_update(task_id, status, use_database: true, **opts)
          return if task_id.nil? || status.nil?

          begin
            if Legion::Settings[:data][:connected] && use_database
              task = Legion::Data::Model::Task[task_id]
              task.update(status: status)
              return true
            end
          rescue StandardError => e
            log.debug("task_update failed, reverting to rmq message, e: #{e.message}")
          end

          update_hash = { task_id: task_id, status: status }
          %i[results payload function_args payload results].each do |column|
            update_hash[column] = opts[column] if opts.key? column
          end
          Legion::Transport::Messages::TaskUpdate.new(**update_hash).publish
        rescue StandardError => e
          handle_exception(e, level: :fatal)
          raise e
        end

        def generate_task_id(function_id:, status: 'task.queued', **opts)
          insert = { status: status, function_id: function_id }
          insert[:payload] = Legion::JSON.dump(opts[:payload]) if opts.key? :payload
          insert[:function_args] = Legion::JSON.dump(opts[:args]) if opts.key? :args
          %i[master_id parent_id relationship_id task_id].each do |column|
            insert[column] = opts[column] if opts.key? column
          end

          { success: true, task_id: Legion::Data::Model::Task.insert(insert), **insert }
        end
      end
    end
  end
end
