# frozen_string_literal: true

module Legion
  module Tools
    class Status < Base
      tool_name 'legion.get_status'
      description 'Get Legion service health status and component info.'
      input_schema(type: 'object', properties: {})

      class << self
        include Legion::Logging::Helper

        def call(**_args)
          status = {
            version:    defined?(Legion::VERSION) ? Legion::VERSION : 'unknown',
            ready:      readiness_check,
            components: components_check,
            node:       node_name
          }
          text_response(status)
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :tool_status_call)
          error_response("Failed to get status: #{e.message}")
        end

        private

        def readiness_check
          Legion::Readiness.ready?
        rescue StandardError
          false
        end

        def components_check
          Legion::Readiness.to_h
        rescue StandardError
          {}
        end

        def node_name
          Legion::Settings[:client][:name]
        rescue StandardError
          'unknown'
        end
      end

      Legion::Tools.register_class(self)
    end
  end
end
