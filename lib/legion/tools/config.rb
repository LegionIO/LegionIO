# frozen_string_literal: true

module Legion
  module Tools
    class Config < Base
      tool_name 'legion.get_config'
      description 'Get Legion configuration (sensitive values are redacted).'
      input_schema(
        properties: {
          section: { type: 'string', description: 'Specific config section (e.g., "transport", "data")' }
        }
      )

      SENSITIVE_KEYS = %i[password secret token key cert private_key api_key].freeze

      class << self
        def call(section: nil)
          settings = Legion::Settings.loader.to_hash

          if section
            key = section.to_sym
            return error_response("Setting '#{section}' not found") unless settings.key?(key)

            value = settings[key]
            value = redact_hash(value) if value.is_a?(Hash)
            text_response({ key: key, value: value })
          else
            text_response(redact_hash(settings))
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: :tool_config_call)
          error_response("Failed to get config: #{e.message}")
        end

        private

        def redact_hash(hash)
          return hash unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(k, v), result|
            result[k] = if v.is_a?(Hash)
                          redact_hash(v)
                        elsif SENSITIVE_KEYS.any? { |s| k.to_s.include?(s.to_s) }
                          '[REDACTED]'
                        else
                          v
                        end
          end
        end
      end

      Legion::Tools.register_class(self)
    end
  end
end
