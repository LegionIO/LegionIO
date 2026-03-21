# frozen_string_literal: true

return unless defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    module GraphQL
      module Types
        class QueryType < BaseObject
          graphql_name 'Query'
          description 'Root query type'

          # ── workers ──────────────────────────────────────────────────────────

          field :workers, [WorkerType], null: false, description: 'List digital workers' do
            argument :status,    String, required: false, description: 'Filter by lifecycle state'
            argument :risk_tier, String, required: false, description: 'Filter by risk tier'
            argument :limit,     Integer, required: false, description: 'Maximum results'
          end

          field :worker, WorkerType, null: true, description: 'Find a digital worker by ID' do
            argument :id, ID, required: true, description: 'Worker ID'
          end

          # ── extensions ───────────────────────────────────────────────────────

          field :extensions, [ExtensionType], null: false, description: 'List loaded extensions' do
            argument :status, String, required: false, description: 'Filter by status'
          end

          field :extension, ExtensionType, null: true, description: 'Find an extension by name' do
            argument :name, String, required: true, description: 'Extension gem name'
          end

          # ── tasks ─────────────────────────────────────────────────────────────

          field :tasks, [TaskType], null: false, description: 'List task records' do
            argument :status, String,  required: false, description: 'Filter by status'
            argument :limit,  Integer, required: false, description: 'Maximum results'
          end

          # ── node ──────────────────────────────────────────────────────────────

          field :node, NodeType, null: true, description: 'Current node information'

          # ── resolvers ────────────────────────────────────────────────────────

          def workers(status: nil, risk_tier: nil, limit: nil)
            Resolvers::Workers.resolve(status: status, risk_tier: risk_tier, limit: limit)
          end

          def worker(id:)
            Resolvers::Workers.find(id: id)
          end

          def extensions(status: nil)
            Resolvers::Extensions.resolve(status: status)
          end

          def extension(name:)
            Resolvers::Extensions.find(name: name)
          end

          def tasks(status: nil, limit: nil)
            Resolvers::Tasks.resolve(status: status, limit: limit)
          end

          def node
            Resolvers::Node.resolve
          end
        end
      end
    end
  end
end
