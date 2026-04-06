# frozen_string_literal: true

module Legion
  module CLI
    class Doctor
      class ApiBindCheck
        LOOPBACK_BINDS = %w[127.0.0.1 ::1 localhost].freeze

        def name
          'API bind address'
        end

        def run
          return skip_result unless defined?(Legion::Settings)

          api_settings = Legion::Settings[:api]
          return skip_result unless api_settings.is_a?(Hash)

          bind = api_settings[:bind]
          return skip_result if bind.nil?

          if LOOPBACK_BINDS.include?(bind)
            Result.new(
              name:    name,
              status:  :pass,
              message: "API bound to loopback (#{bind})"
            )
          elsif api_settings.dig(:auth, :enabled) == true
            Result.new(
              name:    name,
              status:  :pass,
              message: "API bound to #{bind} with auth enabled"
            )
          else
            Result.new(
              name:         name,
              status:       :warn,
              message:      "API bound to non-loopback address (#{bind}) without explicit auth configuration",
              prescription: "Set api.auth.enabled: true or change api.bind to '127.0.0.1'"
            )
          end
        end

        private

        def skip_result
          Result.new(
            name:    name,
            status:  :pass,
            message: 'API settings not loaded'
          )
        end
      end
    end
  end
end
