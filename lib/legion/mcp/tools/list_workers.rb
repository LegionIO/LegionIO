# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListWorkers < ::MCP::Tool
        tool_name 'legion.list_workers'
        description 'List digital workers with optional filtering by team, owner, or lifecycle state.'

        input_schema(
          properties: {
            team:            { type: 'string',  description: 'Filter by team name' },
            owner_msid:      { type: 'string',  description: 'Filter by owner MSID' },
            lifecycle_state: { type: 'string',  description: 'Filter by lifecycle state (bootstrap, active, paused, retired, terminated)' },
            limit:           { type: 'integer', description: 'Max results (default 20, max 100)' }
          }
        )

        class << self
          def call(team: nil, owner_msid: nil, lifecycle_state: nil, limit: 20)
            return error_response('legion-data is not connected') unless data_connected?

            limit   = limit.to_i.clamp(1, 100)
            dataset = Legion::Data::Model::DigitalWorker.order(Sequel.desc(:id))
            dataset = dataset.where(team: team)                       if team
            dataset = dataset.where(owner_msid: owner_msid)           if owner_msid
            dataset = dataset.where(lifecycle_state: lifecycle_state) if lifecycle_state

            text_response(dataset.limit(limit).all.map(&:values))
          rescue StandardError => e
            error_response("Failed to list workers: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError
            false
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
