# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Transport
        def self.registered(app)
          app.get '/api/transport' do
            connected = begin
              Legion::Settings[:transport][:connected]
            rescue StandardError
              false
            end
            session_open = begin
              Legion::Transport::Connection.session_open?
            rescue StandardError
              false
            end
            channel_open = begin
              Legion::Transport::Connection.channel_open?
            rescue StandardError
              false
            end
            connector = defined?(Legion::Transport::TYPE) ? Legion::Transport::TYPE.to_s : 'unknown'

            info = {
              connected:    connected,
              session_open: session_open,
              channel_open: channel_open,
              connector:    connector
            }
            json_response(info)
          end

          app.get '/api/transport/exchanges' do
            exchanges = if defined?(Legion::Transport::Exchange)
                          ObjectSpace.each_object(Class)
                                     .select { |klass| klass < Legion::Transport::Exchange }
                                     .map { |klass| { name: klass.name } }
                                     .sort_by { |h| h[:name].to_s }
                        else
                          []
                        end
            json_response(exchanges)
          end

          app.get '/api/transport/queues' do
            queues = if defined?(Legion::Transport::Queue)
                       ObjectSpace.each_object(Class)
                                  .select { |klass| klass < Legion::Transport::Queue }
                                  .map { |klass| { name: klass.name } }
                                  .sort_by { |h| h[:name].to_s }
                     else
                       []
                     end
            json_response(queues)
          end

          app.post '/api/transport/publish' do
            body = parse_request_body
            halt 422, json_error('missing_field', 'exchange is required', status_code: 422) unless body[:exchange]
            halt 422, json_error('missing_field', 'routing_key is required', status_code: 422) unless body[:routing_key]

            payload = body[:payload] || {}

            message = Legion::Transport::Messages::Dynamic.new(
              exchange:    body[:exchange],
              routing_key: body[:routing_key],
              **payload
            )
            message.publish

            json_response({ published: true, exchange: body[:exchange], routing_key: body[:routing_key] }, status_code: 201)
          rescue StandardError => e
            Legion::Logging.error "API publish error: #{e.message}"
            json_error('publish_error', e.message, status_code: 500)
          end
        end
      end
    end
  end
end
