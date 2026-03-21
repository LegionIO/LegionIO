# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class WorkerType < BaseObject
          graphql_name 'Worker'
          description 'A LegionIO digital worker'

          field :id,         Integer, null: true,  description: 'Worker database ID'
          field :name,       String,  null: true,  description: 'Worker name'
          field :status,     String,  null: true,  description: 'Lifecycle state'
          field :risk_tier,  String,  null: true,  description: 'AIRB risk tier'
          field :team,       String,  null: true,  description: 'Team name'
          field :extension,  String,  null: true,  description: 'Extension name'
          field :created_at, String,  null: true,  description: 'Creation timestamp'
        end
      end
    end
  end
end
