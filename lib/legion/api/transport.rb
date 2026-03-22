# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Transport
        def self.registered(app)
          register_status(app)
          register_discovery(app)
          register_publish(app)
        end

        def self.register_status(app)
          app.get '/api/transport' do
            connected = begin
              Legion::Settings[:transport][:connected]
            rescue StandardError => e
              Legion::Logging.debug "Transport#status failed to read connected setting: #{e.message}" if defined?(Legion::Logging)
              false
            end
            session_open = begin
              Legion::Transport::Connection.session_open?
            rescue StandardError => e
              Legion::Logging.debug "Transport#status failed to check session_open: #{e.message}" if defined?(Legion::Logging)
              false
            end
            channel_open = begin
              Legion::Transport::Connection.channel_open?
            rescue StandardError => e
              Legion::Logging.debug "Transport#status failed to check channel_open: #{e.message}" if defined?(Legion::Logging)
              false
            end
            connector = defined?(Legion::Transport::TYPE) ? Legion::Transport::TYPE.to_s : 'unknown'

            json_response({ connected: connected, session_open: session_open,
                            channel_open: channel_open, connector: connector })
          end
        end

        def self.register_discovery(app)
          app.get '/api/transport/exchanges' do
            klass = defined?(Legion::Transport::Exchange) ? Legion::Transport::Exchange : nil
            json_response(klass ? transport_subclasses(klass) : [])
          end

          app.get '/api/transport/queues' do
            klass = defined?(Legion::Transport::Queue) ? Legion::Transport::Queue : nil
            json_response(klass ? transport_subclasses(klass) : [])
          end
        end

        def self.register_publish(app)
          app.post '/api/transport/publish' do
            Legion::Logging.debug "API: POST /api/transport/publish params=#{params.keys}"
            body = parse_request_body
            unless body[:exchange]
              Legion::Logging.warn 'API POST /api/transport/publish returned 422: exchange is required'
              halt 422, json_error('missing_field', 'exchange is required', status_code: 422)
            end
            unless body[:routing_key]
              Legion::Logging.warn 'API POST /api/transport/publish returned 422: routing_key is required'
              halt 422, json_error('missing_field', 'routing_key is required', status_code: 422)
            end

            message = Legion::Transport::Messages::Dynamic.new(
              exchange: body[:exchange], routing_key: body[:routing_key], **(body[:payload] || {})
            )
            message.publish
            Legion::Logging.info "API: published message to exchange=#{body[:exchange]} routing_key=#{body[:routing_key]}"
            json_response({ published: true, exchange: body[:exchange], routing_key: body[:routing_key] }, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API POST /api/transport/publish: #{e.class} — #{e.message}"
            json_error('publish_error', e.message, status_code: 500)
          end
        end

        class << self
          private :register_status, :register_discovery, :register_publish
        end
      end
    end
  end
end
