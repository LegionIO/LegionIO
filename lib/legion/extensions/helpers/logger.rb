# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Helpers
      module Logger
        include Legion::Extensions::Helpers::Base
        include Legion::Logging::Helper

        def handle_runner_exception(exception, task_id: nil, **opts)
          handle_exception(exception, task_id: task_id, **opts)

          unless task_id.nil?
            Legion::Transport::Messages::TaskLog.new(
              task_id:      task_id,
              runner_class: to_s,
              entry:        { exception: true, message: exception.message, **opts }
            ).publish
          end

          raise Legion::Exception::HandledTask
        end
      end
    end
  end
end
