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
        include Legion::Logging::Helper

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

        def redact_value(key, value)
          normalized_key = key.to_s.downcase
          if value.is_a?(Hash)
            redact_hash(value)
          elsif value.is_a?(Array)
            value.map { |elem| elem.is_a?(Hash) ? redact_hash(elem) : elem }
          elsif SENSITIVE_KEYS.any? { |s| normalized_key.include?(s.to_s) }
            '[REDACTED]'
          else
            value
          end
        end

        def redact_hash(hash)
          return hash unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(k, v), result|
            result[k] = redact_value(k, v)
          end
        end
      end

      Legion::Tools.register_class(self)
    end
  end
end
