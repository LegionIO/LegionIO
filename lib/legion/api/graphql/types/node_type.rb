# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class NodeType < BaseObject
          graphql_name 'Node'
          description 'A LegionIO node'

          field :name,    String,  null: true,  description: 'Node name'
          field :version, String,  null: true,  description: 'LegionIO version'
          field :uptime,  Integer, null: true,  description: 'Uptime in seconds'
          field :ready,   Boolean, null: false, description: 'Whether the node is ready'
        end
      end
    end
  end
end
