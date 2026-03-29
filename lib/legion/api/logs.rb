# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Logs
        VALID_LEVELS = %w[error warn].freeze

        def self.registered(app)
          register_ingest(app)
        end

        def self.register_ingest(app)
          app.post '/api/logs' do
            body = parse_request_body
            Legion::API::Routes::Logs.validate_log_request!(self, body)

            level   = body[:level].to_s
            source  = body[:source].to_s.then { |s| s.empty? ? 'unknown' : s }
            payload = Legion::API::Routes::Logs.build_log_payload(body, level, source)
            key     = Legion::API::Routes::Logs.routing_key_for(body, level, source)

            Legion::Transport::Messages::Dynamic.new(
              exchange: 'legion.logging', routing_key: key, **payload
            ).publish

            json_response({ published: true, routing_key: key }, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/logs: #{e.class} - #{e.message}" if defined?(Legion::Logging)
            halt 500, json_error('publish_error', e.message, status_code: 500)
          end
        end

        def self.validate_log_request!(ctx, body)
          unless VALID_LEVELS.include?(body[:level].to_s)
            Legion::Logging.warn 'API POST /api/logs returned 422: level must be error or warn' if defined?(Legion::Logging)
            ctx.halt 422, ctx.json_error('invalid_level', 'level must be "error" or "warn"', status_code: 422)
          end

          return unless body[:message].to_s.strip.empty?

          Legion::Logging.warn 'API POST /api/logs returned 422: message is required' if defined?(Legion::Logging)
          ctx.halt 422, ctx.json_error('missing_field', 'message is required', status_code: 422)
        end

        def self.build_log_payload(body, level, source)
          payload = {
            level:           level,
            message:         body[:message].to_s,
            timestamp:       Time.now.utc.iso8601(3),
            node:            Legion::Settings[:client][:name],
            legion_versions: Legion::Logging::EventBuilder.send(:legion_versions),
            ruby_version:    "#{RUBY_VERSION} #{RUBY_PLATFORM}",
            pid:             ::Process.pid,
            component_type:  body[:component_type].to_s.then { |t| t.empty? ? 'cli' : t },
            source:          source
          }
          payload[:exception_class] = body[:exception_class] if body[:exception_class]
          payload[:backtrace]       = body[:backtrace]        if body[:backtrace]
          payload[:command]         = body[:command]          if body[:command]
          payload[:error_fingerprint] = fingerprint_for(body, payload) if body[:exception_class]
          payload
        end

        def self.fingerprint_for(body, payload)
          Legion::Logging::EventBuilder.fingerprint(
            exception_class: body[:exception_class].to_s,
            message:         body[:message].to_s,
            caller_file:     '',
            caller_line:     0,
            caller_function: '',
            gem_name:        '',
            component_type:  payload[:component_type],
            backtrace:       Array(body[:backtrace])
          )
        end

        def self.routing_key_for(body, level, source)
          kind = body[:exception_class] ? 'exception' : 'log'
          "legion.logging.#{kind}.#{level}.cli.#{source}"
        end

        class << self
          private :register_ingest, :fingerprint_for
        end
      end
    end
  end
end
