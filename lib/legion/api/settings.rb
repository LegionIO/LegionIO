# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Settings
        SENSITIVE_KEYS = %i[password secret token key cert private_key api_key].freeze
        READONLY_SECTIONS = %i[crypt transport identity rbac api].freeze

        def self.registered(app)
          app.get '/api/settings' do
            redacted = redact_hash(Legion::Settings.loader.to_hash)
            json_response(redacted)
          end

          app.get '/api/settings/:key' do
            key = params[:key].to_sym
            settings_hash = Legion::Settings.loader.to_hash
            unless settings_hash.key?(key)
              Legion::Logging.warn "API GET /api/settings/#{key} returned 404: setting not found"
              halt 404, json_error('not_found', "setting '#{key}' not found", status_code: 404)
            end

            value = Legion::Settings[key]
            value = redact_hash(value) if value.is_a?(Hash)
            json_response({ key: key, value: value })
          end

          app.put '/api/settings/:key' do
            Legion::Logging.debug "API: PUT /api/settings/#{params[:key]} params=#{params.keys}"
            key = params[:key].to_sym

            if READONLY_SECTIONS.include?(key)
              Legion::Logging.warn "API PUT /api/settings/#{key} returned 403: read-only section"
              halt 403, json_error('forbidden', "setting '#{key}' is read-only via API", status_code: 403)
            end

            body = parse_request_body
            unless body.key?(:value)
              Legion::Logging.warn "API PUT /api/settings/#{key} returned 422: value is required"
              halt 422, json_error('missing_field', 'value is required', status_code: 422)
            end

            Legion::Settings.loader[key] = body[:value]
            Legion::Logging.info "API: updated setting #{key}"
            json_response({ key: key, value: body[:value] })
          end
        end
      end
    end
  end
end
