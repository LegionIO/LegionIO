# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Apollo
        def self.registered(app)
          app.helpers ApolloHelpers
          register_status_route(app)
          register_query_route(app)
          register_ingest_route(app)
          register_related_route(app)
        end

        def self.register_status_route(app)
          app.get '/api/apollo/status' do
            if apollo_loaded?
              json_response({ available: true, data_connected: apollo_data_connected? })
            else
              json_response({ available: false }, status_code: 503)
            end
          end
        end

        def self.register_query_route(app)
          app.post '/api/apollo/query' do
            halt 503, json_error('apollo_unavailable', 'apollo is not available', status_code: 503) unless apollo_loaded?

            body = parse_request_body
            result = apollo_runner.handle_query(
              query:          body[:query],
              limit:          body[:limit] || 10,
              min_confidence: body[:min_confidence] || 0.3,
              status:         body[:status] || [:confirmed],
              tags:           body[:tags],
              domain:         body[:domain],
              agent_id:       body[:agent_id] || 'api'
            )
            json_response(result)
          end
        end

        def self.register_ingest_route(app)
          app.post '/api/apollo/ingest' do
            halt 503, json_error('apollo_unavailable', 'apollo is not available', status_code: 503) unless apollo_loaded?

            body = parse_request_body
            result = apollo_runner.handle_ingest(
              content:          body[:content],
              content_type:     body[:content_type] || :observation,
              tags:             body[:tags] || [],
              source_agent:     body[:source_agent] || 'api',
              source_provider:  body[:source_provider],
              source_channel:   body[:source_channel] || 'rest_api',
              knowledge_domain: body[:knowledge_domain],
              context:          body[:context] || {}
            )
            json_response(result, status_code: 201)
          end
        end

        def self.register_related_route(app)
          app.get '/api/apollo/entries/:id/related' do
            halt 503, json_error('apollo_unavailable', 'apollo is not available', status_code: 503) unless apollo_loaded?

            result = apollo_runner.related_entries(
              entry_id:       params[:id].to_i,
              relation_types: params[:relation_types]&.split(','),
              depth:          (params[:depth] || 2).to_i
            )
            json_response(result)
          end
        end
      end

      module ApolloHelpers
        def apollo_loaded?
          defined?(Legion::Extensions::Apollo::Runners::Knowledge) && apollo_data_connected?
        end

        def apollo_data_connected?
          defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && !Legion::Data.connection.nil?
        rescue StandardError
          false
        end

        def apollo_runner
          @apollo_runner ||= Object.new.extend(Legion::Extensions::Apollo::Runners::Knowledge)
        end
      end
    end
  end
end
