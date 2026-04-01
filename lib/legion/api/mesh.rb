# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Mesh
        def self.registered(app)
          app.get '/api/mesh/status' do
            require_mesh!
            result = Legion::Extensions::Mesh::Runners::Mesh.mesh_status
            json_response(result)
          end

          app.get '/api/mesh/peers' do
            require_mesh!
            registry = Legion::Extensions::Mesh.mesh_registry
            agents = registry.all_agents.map do |agent|
              agent.slice(:agent_id, :capabilities, :endpoint, :status, :last_seen, :registered_at)
            end
            json_response(agents)
          end
        end
      end
    end
  end
end
