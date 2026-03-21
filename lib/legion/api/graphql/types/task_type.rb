# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class TaskType < BaseObject
          graphql_name 'Task'
          description 'A LegionIO task execution record'

          field :id,           Integer, null: true, description: 'Task database ID'
          field :status,       String,  null: true, description: 'Task status'
          field :extension,    String,  null: true, description: 'Extension name'
          field :runner,       String,  null: true, description: 'Runner namespace'
          field :function,     String,  null: true, description: 'Function name'
          field :created_at,   String,  null: true, description: 'Creation timestamp'
          field :completed_at, String,  null: true, description: 'Completion timestamp'
        end
      end
    end
  end
end
