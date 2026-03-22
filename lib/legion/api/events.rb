# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Events
        BUFFER_SIZE = 100

        class << self
          def event_buffer
            @event_buffer ||= []
          end

          def buffer_mutex
            @buffer_mutex ||= Mutex.new
          end

          def push_event(event)
            buffer_mutex.synchronize do
              event_buffer.push(event)
              event_buffer.shift if event_buffer.length > BUFFER_SIZE
            end
          end

          def recent_events(count = 25)
            buffer_mutex.synchronize do
              event_buffer.last(count)
            end
          end

          def install_listener
            return if @listener_installed
            return unless defined?(Legion::Events)

            Legion::Events.on('*') do |event|
              push_event(event.transform_keys(&:to_s))
            end
            @listener_installed = true
          end

          def registered(app)
            install_listener if defined?(Legion::Events)

            app.get '/api/events' do
              content_type 'text/event-stream'
              headers 'Cache-Control'     => 'no-cache',
                      'Connection'        => 'keep-alive',
                      'X-Accel-Buffering' => 'no'

              queue = Queue.new
              listener = Legion::Events.on('*') do |event|
                queue.push(event)
              end

              stream do |out|
                Thread.new do
                  loop do
                    event = queue.pop
                    data = Legion::JSON.dump(event.transform_keys(&:to_s))
                    out << "event: #{event[:event]}\ndata: #{data}\n\n"
                  rescue IOError, Errno::EPIPE => e
                    Legion::Logging.debug "Events SSE stream broken for #{event[:event]}: #{e.message}" if defined?(Legion::Logging)
                    break
                  end
                ensure
                  Legion::Events.off('*', listener)
                end

                out.callback { Legion::Events.off('*', listener) }
                out.errback { Legion::Events.off('*', listener) }
              end
            end

            app.get '/api/events/recent' do
              count = (params[:count] || 25).to_i
              count = [count, BUFFER_SIZE].min
              events = Events.recent_events(count)
              json_response(events)
            end
          end
        end
      end
    end
  end
end
