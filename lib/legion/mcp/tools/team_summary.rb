# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class TeamSummary < ::MCP::Tool
        tool_name 'legion.team_summary'
        description 'Get a summary of all digital workers for a team, including lifecycle state breakdown.'

        input_schema(
          properties: {
            team: { type: 'string', description: 'Team name to summarize' }
          },
          required:   ['team']
        )

        class << self
          def call(team:)
            return error_response('legion-data is not connected') unless data_connected?

            workers = Legion::DigitalWorker.by_team(team: team).all
            breakdown = workers.each_with_object(Hash.new(0)) { |w, counts| counts[w.values[:lifecycle_state]] += 1 }

            text_response({
                            team:             team,
                            total:            workers.size,
                            lifecycle_states: breakdown,
                            workers:          workers.map { |w| w.values.slice(:worker_id, :name, :lifecycle_state, :owner_msid, :business_role) }
                          })
          rescue StandardError => e
            error_response("Failed to fetch team summary: #{e.message}")
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
