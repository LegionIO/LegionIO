# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Settings
        SENSITIVE_KEYS = %i[password secret token key cert private_key api_key].freeze
        READONLY_SECTIONS = %i[crypt transport].freeze

        def self.registered(app)
          app.get '/api/settings' do
            redacted = redact_hash(Legion::Settings.loader.to_hash)
            json_response(redacted)
          end

          app.get '/api/settings/:key' do
            key = params[:key].to_sym
            settings_hash = Legion::Settings.loader.to_hash
            halt 404, json_error('not_found', "setting '#{key}' not found", status_code: 404) unless settings_hash.key?(key)

            value = Legion::Settings[key]
            value = redact_hash(value) if value.is_a?(Hash)
            json_response({ key: key, value: value })
          end

          app.put '/api/settings/:key' do
            key = params[:key].to_sym

            halt 403, json_error('forbidden', "setting '#{key}' is read-only via API", status_code: 403) if READONLY_SECTIONS.include?(key)

            body = parse_request_body
            halt 422, json_error('missing_field', 'value is required', status_code: 422) unless body.key?(:value)

            Legion::Settings.loader[key] = body[:value]
            json_response({ key: key, value: body[:value] })
          end
        end

        private

        def redact_hash(hash)
          return hash unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(k, v), result|
            key_sym = k.to_sym
            result[k] = if v.is_a?(Hash)
                          redact_hash(v)
                        elsif SENSITIVE_KEYS.any? { |s| key_sym.to_s.include?(s.to_s) }
                          '[REDACTED]'
                        else
                          v
                        end
          end
        end
      end
    end
  end
end
