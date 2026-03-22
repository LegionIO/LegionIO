# frozen_string_literal: true

module Legion
  module Runner
    module Status
      def self.update(task_id:, status: 'task.completed', **)
        Legion::Logging.debug "[Status] transition task_id=#{task_id} -> #{status}" if defined?(Legion::Logging)
        return if status.nil?

        if Legion::Settings[:data][:connected]
          update_db(task_id: task_id, status: status, **)
        else
          update_rmq(task_id: task_id, status: status, **)
        end
      end

      def self.update_rmq(task_id:, status: 'task.completed', **)
        return if status.nil?

        retries = 0
        Legion::Transport::Messages::TaskUpdate.new(task_id: task_id, status: status, **).publish
      rescue StandardError => e
        retries += 1
        Legion::Logging.warn "[Status] update_rmq failed (attempt #{retries}/3): #{e.message}"
        Legion::Logging.fatal e.backtrace
        retry if retries < 3
      end

      def self.update_db(task_id:, status: 'task.completed', **)
        return if status.nil?

        task = Legion::Data::Model::Task[task_id]
        task.update(status: status)
      rescue StandardError => e
        Legion::Logging.warn "[Status] update_db failed for task_id=#{task_id}: #{e.message}"
        Legion::Logging.warn '[Status] falling back to RabbitMQ update'
        Legion::Logging.warn e.backtrace
        update_rmq(task_id: task_id, status: status, **)
      end

      def self.generate_task_id(runner_class:, function:, status: 'task.queued', **opts)
        Legion::Logging.debug "[Status] generate_task_id: #{runner_class}##{function} status=#{status}" if defined?(Legion::Logging)
        return nil unless Legion::Settings[:data][:connected]

        runner = Legion::Data::Model::Runner.where(namespace: runner_class.to_s.downcase).first
        return nil if runner.nil?

        function = Legion::Data::Model::Function.where(runner_id: runner.values[:id], name: function).first
        return nil if function.nil?

        insert = { status: status, function_id: function.values[:id] }
        insert[:parent_id] = opts[:task_id] if opts.key? :task_id
        insert[:master_id] = opts[:task_id] if opts.key? :task_id
        insert[:payload] = Legion::JSON.dump(opts[:payload]) if opts.key? :payload

        %i[function_args master_id parent_id relationship_id].each do |column|
          next unless opts.key? column

          insert[column] = opts[column].is_a?(Hash) ? Legion::JSON.dump(opts[column]) : opts[column]
        end

        { success: true, task_id: Legion::Data::Model::Task.insert(insert), **insert }
      rescue StandardError => e
        Legion::Logging.error e.message
        Legion::Logging.error e.backtrace
        raise(e)
      end
    end
  end
end
