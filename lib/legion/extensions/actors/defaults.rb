# frozen_string_literal: true

module Legion
  module Extensions
    module Actors
      module Defaults
        def use_runner?
          true
        end
        # module_function :use_runner?

        def check_subtask?
          true
        end
        # module_function :check_subtask?

        def generate_task?
          false
        end
        # module_function :generate_task?

        def enabled?
          true
        end
        # module_function :enabled?
        # extend self
      end
    end
  end
end
