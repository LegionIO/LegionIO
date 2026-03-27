# frozen_string_literal: true

require 'securerandom'

module Legion
  module Extensions
    module Actors
      module AbsorberDispatch
        module_function

        def dispatch(input:, job_id: nil, context: {})
          job_id ||= SecureRandom.hex(8)
          absorber_class = Absorbers::PatternMatcher.resolve(input)

          unless absorber_class
            publish_event("absorb.failed.#{job_id}", job_id: job_id, error: 'no handler found for input')
            return { success: false, error: 'no handler found for input', job_id: job_id }
          end

          absorber = absorber_class.new
          absorber.job_id = job_id
          result = absorber.handle(url: input, content: context[:content],
                                   metadata: context[:metadata] || {}, context: context)
          publish_event("absorb.complete.#{job_id}", job_id: job_id, absorber: absorber_class.name,
                                                     result: result)
          { success: true, job_id: job_id, absorber: absorber_class.name, result: result }
        rescue StandardError => e
          Legion::Logging.error("AbsorberDispatch failed: #{e.message}") if defined?(Legion::Logging)
          publish_event("absorb.failed.#{job_id}", job_id: job_id, error: e.message)
          { success: false, job_id: job_id, error: e.message }
        end

        def publish_event(routing_key, **payload)
          return unless defined?(Legion::Transport::Message)

          Legion::Transport::Message.new(routing_key: routing_key, **payload).publish
        rescue StandardError => e
          Legion::Logging.warn("AbsorberDispatch publish failed: #{e.message}") if defined?(Legion::Logging)
        end
      end
    end
  end
end
