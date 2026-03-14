# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class WorkerLifecycle < ::MCP::Tool
        tool_name 'legion.worker_lifecycle'
        description 'Transition a digital worker to a new lifecycle state (bootstrap, active, paused, retired, terminated).'

        input_schema(
          properties: {
            worker_id: { type: 'string', description: 'UUID of the digital worker' },
            to_state:  { type: 'string', description: 'Target lifecycle state' },
            by:        { type: 'string', description: 'MSID or identifier of the person performing the transition' },
            reason:    { type: 'string', description: 'Optional reason for the transition' }
          },
          required:   %w[worker_id to_state by]
        )

        class << self
          def call(worker_id:, to_state:, by:, reason: nil)
            return error_response('legion-data is not connected') unless data_connected?

            worker = Legion::DigitalWorker.find(worker_id: worker_id)
            return error_response("Worker not found: #{worker_id}") unless worker

            updated = Legion::DigitalWorker::Lifecycle.transition!(worker, to_state: to_state, by: by, reason: reason)
            text_response(updated.values)
          rescue Legion::DigitalWorker::Lifecycle::InvalidTransition => e
            error_response("Invalid transition: #{e.message}")
          rescue StandardError => e
            error_response("Lifecycle transition failed: #{e.message}")
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
