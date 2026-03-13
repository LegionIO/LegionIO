# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Actors
      class Once
        include Legion::Extensions::Actors::Base

        def initialize
          return unless enabled?

          if respond_to? :functions
            functions.each do
              function
              @task = Concurrent::ScheduledTask.execute(delay) do
                use_runner? ? runner : manual
              end
            end
          else
            @task = Concurrent::ScheduledTask.execute(delay) do
              use_runner? ? runner : manual
            end
          end
        rescue StandardError => e
          Legion::Logging.error e
        end

        def delay
          1.0
        end

        def cancel
          return unless enabled?

          @task.cancel unless @task.cancelled?
        end
      end
    end
  end
end
