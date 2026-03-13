# frozen_string_literal: true

module Legion
  module Runner
    module Status
      def self.update(task_id:, status: 'task.completed', **opts)
        Legion::Logging.debug "Legion::Runner::Status.update called, #{task_id}, status: #{status}, #{opts}"
        return if status.nil?

        if Legion::Settings[:data][:connected]
          update_db(task_id: task_id, status: status, **opts)
        else
          update_rmq(task_id: task_id, status: status, **opts)
        end
      end

      def self.update_rmq(task_id:, status: 'task.completed', **)
        return if status.nil?

        Legion::Transport::Messages::TaskUpdate.new(task_id: task_id, status: status, **).publish
      rescue StandardError => e
        Legion::Logging.fatal e.message
        Legion::Logging.fatal e.backtrace
        retries ||= 0
        Legion::Logging.fatal 'Will retry in 3 seconds' if retries < 5
        sleep(3)
        retry if (retries += 1) < 5
      end

      def self.update_db(task_id:, status: 'task.completed', **)
        return if status.nil?

        task = Legion::Data::Model::Task[task_id]
        task.update(status: status)
      rescue StandardError => e
        Legion::Logging.warn e.message
        Legion::Logging.warn 'Legion::Runner.update_status_db failed, defaulting to rabbitmq'
        Legion::Logging.warn e.backtrace
        update_rmq(task_id: task_id, status: status, **)
      end

      def self.generate_task_id(runner_class:, function:, status: 'task.queued', **opts)
        Legion::Logging.debug "Legion::Runner::Status.generate_task_id called, #{runner_class}, #{function}, status: #{status}, #{opts}"
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
