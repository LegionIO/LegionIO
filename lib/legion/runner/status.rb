# frozen_string_literal: true

require 'legion/transport/task_protocol'
require 'legion/data/task_execution'
require 'securerandom'

module Legion
  module Runner
    module Status
      extend Legion::Transport::TaskProtocol::Helper

      def self.data_connected?
        Legion::Settings[:data].is_a?(Hash) && Legion::Settings[:data][:connected] == true
      end

      def self.update(task_id:, status:, expected_status: nil, token: nil, **values)
        raise ArgumentError, 'task_id and status are required' if task_id.nil? || status.nil?

        if data_connected?
          update_db(task_id: task_id, status: status, expected_status: expected_status, token: token, **values)
        else
          update_rmq(task_id: task_id, status: status, expected_status: expected_status, token: token, **values)
        end
      end

      def self.update_rmq(task_id:, status:, **values)
        Legion::Transport::Messages::TaskUpdate.new(**values, task_id: task_id, status: status).publish!
      end

      def self.update_db(task_id:, status:, expected_status: nil, token: nil, **values)
        Legion::Data::TaskExecution.transition_task(task_id: task_id, status: status, expected_status: expected_status,
                                                    token: token, values: values.slice(:results, :payload, :function_args))
      end

      def self.generate_task_id(runner_class:, function:, status: nil, **opts)
        return unless data_connected?

        runner = Legion::Data::Model::Runner[namespace: runner_class.to_s]
        raise ArgumentError, "unregistered runner #{runner_class}" unless runner

        function_row = Legion::Data::Model::Function.first(runner_id: runner.values[:id], name: function.to_s)
        raise ArgumentError, "unregistered function #{runner_class}##{function}" unless function_row

        values = opts.slice(:master_id, :parent_id, :relationship_id, :deadline_at).compact
        values.merge!(status: status || task_status(name: :queued), function_id: function_row.values[:id])
        values[:payload] = opts[:payload] if opts.key?(:payload)
        values[:function_args] = opts[:args] || opts[:function_args] if opts.key?(:args) || opts.key?(:function_args)
        key = opts[:idempotency_key] || opts[:message_id] || SecureRandom.uuid
        created = Legion::Data::TaskExecution.create_task(values: values, idempotency_key: "runner:#{key}")
        { success: true, task_id: created[:task][:id], **created }
      end
    end
  end
end
