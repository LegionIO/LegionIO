# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Gaia
        def self.registered(app)
          register_status_route(app)
          register_ticks_route(app)
          register_channels_route(app)
          register_buffer_route(app)
          register_sessions_route(app)
          register_teams_webhook_route(app)
        end

        def self.register_ticks_route(app)
          app.get '/api/gaia/ticks' do
            halt 503, json_error('gaia_unavailable', 'gaia is not started', status_code: 503) unless gaia_available?

            limit = (params[:limit] || 50).to_i.clamp(1, 200)
            events = defined?(Legion::Gaia) ? Legion::Gaia.tick_history&.recent(limit: limit) : []
            json_response({ events: events || [] })
          end
        end

        def self.register_status_route(app)
          app.get '/api/gaia/status' do
            if gaia_available?
              json_response(Legion::Gaia.status)
            else
              json_response({ started: false }, status_code: 503)
            end
          end
        end

        def self.register_channels_route(app)
          app.helpers GaiaHelpers

          app.get '/api/gaia/channels' do
            halt 503, json_error('gaia_unavailable', 'gaia is not started', status_code: 503) unless gaia_available?

            registry = Legion::Gaia.channel_registry
            return json_response({ channels: [] }) unless registry

            channels = registry.active_channels.map do |ch_id|
              adapter = registry.adapter_for(ch_id)
              build_channel_info(ch_id, adapter)
            end

            json_response({ channels: channels, count: channels.size })
          end
        end

        def self.register_buffer_route(app)
          app.get '/api/gaia/buffer' do
            halt 503, json_error('gaia_unavailable', 'gaia is not started', status_code: 503) unless gaia_available?

            buffer = Legion::Gaia.sensory_buffer
            json_response({
                            depth:    buffer&.size || 0,
                            empty:    buffer.nil? || buffer.empty?,
                            max_size: gaia_buffer_max_size
                          })
          end
        end

        def self.register_sessions_route(app)
          app.get '/api/gaia/sessions' do
            halt 503, json_error('gaia_unavailable', 'gaia is not started', status_code: 503) unless gaia_available?

            store = Legion::Gaia.session_store
            json_response({
                            count:  store&.size || 0,
                            active: gaia_available?
                          })
          end
        end

        def self.register_teams_webhook_route(app)
          app.post '/api/channels/teams/webhook' do
            Legion::Logging.debug "API: POST /api/channels/teams/webhook params=#{params.keys}"
            body = request.body.read
            activity = Legion::JSON.load(body)

            adapter = Routes::Gaia.teams_adapter
            unless adapter
              Legion::Logging.warn 'API POST /api/channels/teams/webhook returned 503: teams adapter not available'
              halt 503, json_response({ error: 'teams adapter not available' }, status_code: 503)
            end

            input_frame = adapter.translate_inbound(activity)
            Legion::Gaia.sensory_buffer&.push(input_frame) if defined?(Legion::Gaia)
            Legion::Logging.info "API: accepted Teams webhook frame_id=#{input_frame&.id}"
            json_response({ status: 'accepted', frame_id: input_frame&.id })
          end
        end

        def self.teams_adapter
          return nil unless defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:channel_registry)
          return nil unless Legion::Gaia.channel_registry

          Legion::Gaia.channel_registry.adapter_for(:teams)
        rescue StandardError => e
          Legion::Logging.warn "Gaia#teams_adapter failed: #{e.message}" if defined?(Legion::Logging)
          nil
        end

        module GaiaHelpers
          def gaia_available?
            defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
          end

          def gaia_buffer_max_size
            return nil unless defined?(Legion::Gaia::SensoryBuffer)

            Legion::Gaia::SensoryBuffer::MAX_BUFFER_SIZE
          rescue NameError
            nil
          end

          def build_channel_info(channel_id, adapter)
            info = { id: channel_id, started: adapter&.started? || false }
            info[:capabilities] = adapter.capabilities if adapter.respond_to?(:capabilities)
            info[:type] = adapter.class.name.split('::').last if adapter
            info
          end
        end
      end
    end
  end
end
