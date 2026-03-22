# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Gaia
        def self.registered(app)
          app.get '/api/gaia/status' do
            if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
              json_response(Legion::Gaia.status)
            else
              json_response({ started: false }, status_code: 503)
            end
          end

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
      end
    end
  end
end
