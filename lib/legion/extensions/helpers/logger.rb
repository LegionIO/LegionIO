# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module Logger
        include Legion::Logging::Helper

        def handle_exception(exception, task_id: nil, **opts)
          log.error exception.message + " for task_id: #{task_id} but was logged "
          log.error exception.backtrace[0..10]
          log.error opts

          unless task_id.nil?
            Legion::Transport::Messages::TaskLog.new(
              task_id:      task_id,
              runner_class: to_s,
              entry:        {
                exception: true,
                message:   exception.message,
                **opts
              }
            ).publish
          end

          raise Legion::Exception::HandledTask
        end
      end
    end
  end
end
