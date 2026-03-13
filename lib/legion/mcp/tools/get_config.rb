# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetConfig < ::MCP::Tool
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
              unless settings.key?(key)
                return error_response("Setting '#{section}' not found")
              end

              value = settings[key]
              value = redact_hash(value) if value.is_a?(Hash)
              text_response({ key: key, value: value })
            else
              text_response(redact_hash(settings))
            end
          rescue StandardError => e
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

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
