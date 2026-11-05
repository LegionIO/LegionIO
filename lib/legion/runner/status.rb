# frozen_string_literal: true

require 'legion/transport/task/protocol'
require 'legion/transport/messages/task_update'

module Legion
  module Runner
    module Status
      extend Legion::Transport::Task::Protocol::Helper

      def self.data_connected?
        Legion::Settings[:data].is_a?(Hash) && Legion::Settings[:data][:connected] == true
      end

      def self.update(task_id:, status:, **values)
        raise ArgumentError, 'task_id and status are required' if task_id.nil? || status.nil?

        if data_connected?
          update_db(task_id: task_id, status: status, **values)
        else
          update_rmq(task_id: task_id, status: status, **values)
        end
      end

      def self.update_rmq(task_id:, status:, **values)
        Legion::Transport::Messages::TaskUpdate.new(**values, task_id: task_id, status: status).publish!
      end

      def self.update_db(task_id:, status:, **values)
        attributes = values.slice(:results, :payload, :function_args)
        attributes.transform_values! { |value| value.is_a?(Hash) ? Legion::JSON.dump(value) : value }
        Legion::Data::Model::Task[task_id].update(attributes.merge(status: status)).values
      end

      def self.generate_task_id(runner_class:, function:, status: nil, **opts)
        return unless data_connected?

        runner = Legion::Data::Model::Runner[namespace: runner_class.to_s]
        raise ArgumentError, "unregistered runner #{runner_class}" unless runner

        function_row = Legion::Data::Model::Function.first(runner_id: runner.values[:id], name: function.to_s)
        raise ArgumentError, "unregistered function #{runner_class}##{function}" unless function_row

        values = opts.slice(:master_id, :parent_id, :relationship_id).compact
        values.merge!(status: status || task_status(name: :queued), function_id: function_row.values[:id])
        values[:payload] = opts[:payload] if opts.key?(:payload)
        values[:function_args] = opts[:args] || opts[:function_args] if opts.key?(:args) || opts.key?(:function_args)
        values.transform_values! { |value| value.is_a?(Hash) ? Legion::JSON.dump(value) : value }
        task = Legion::Data::Model::Task.create(values).values
        { success: true, task_id: task[:id], task: task }
      end
    end
  end
end
