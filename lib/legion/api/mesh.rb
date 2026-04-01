# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Mesh
        @cache = {}
        @cache_mutex = Mutex.new
        MESH_CACHE_TTL = 10

        def self.cached_fetch(key)
          @cache_mutex.synchronize do
            entry = @cache[key]
            return entry[:data] if entry && (Time.now - entry[:at]) < MESH_CACHE_TTL
          end

          data = yield
          @cache_mutex.synchronize { @cache[key] = { data: data, at: Time.now } }
          data
        end

        def self.registered(app)
          app.get '/api/mesh/status' do
            require_mesh!
            result = Mesh.cached_fetch(:status) do
              Legion::Ingress.run(
                runner_class: 'Legion::Extensions::Mesh::Runners::Mesh',
                function:     'mesh_status',
                source:       :api,
                payload:      {}
              )
            end
            json_response(result)
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'GET /api/mesh/status', component_type: :api)
            json_error('mesh_error', e.message, status_code: 500)
          end

          app.get '/api/mesh/peers' do
            require_mesh!
            result = Mesh.cached_fetch(:peers) do
              Legion::Ingress.run(
                runner_class: 'Legion::Extensions::Mesh::Runners::Mesh',
                function:     'find_agents',
                source:       :api,
                payload:      { capability: nil }
              )
            end
            json_response(result)
          rescue StandardError => e
            Legion::Logging.log_exception(e, payload_summary: 'GET /api/mesh/peers', component_type: :api)
            json_error('mesh_error', e.message, status_code: 500)
          end
        end
      end
    end
  end
end
