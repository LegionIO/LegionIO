# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class UpdateSchedule < ::MCP::Tool
        tool_name 'legion.update_schedule'
        description 'Update an existing schedule.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Schedule ID' },
            cron: { type: 'string', description: 'New cron expression' },
            interval: { type: 'integer', description: 'New interval in seconds' },
            active: { type: 'boolean', description: 'Active status' },
            function_id: { type: 'integer', description: 'New function ID' },
            payload: { type: 'object', description: 'New payload', additionalProperties: true }
          },
          required: ['id']
        )

        class << self
          def call(id:, **attrs)
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('lex-scheduler is not loaded') unless scheduler_loaded?

            record = Legion::Extensions::Scheduler::Data::Model::Schedule[id.to_i]
            return error_response("Schedule #{id} not found") unless record

            updates = {}
            updates[:cron] = attrs[:cron] if attrs.key?(:cron)
            updates[:interval] = attrs[:interval].to_i if attrs.key?(:interval)
            updates[:active] = attrs[:active] if attrs.key?(:active)
            updates[:function_id] = attrs[:function_id].to_i if attrs.key?(:function_id)
            updates[:payload] = Legion::JSON.dump(attrs[:payload]) if attrs.key?(:payload)

            record.update(updates) unless updates.empty?
            record.refresh
            text_response(record.values)
          rescue StandardError => e
            error_response("Failed to update schedule: #{e.message}")
          end

          private

          def data_connected? = (Legion::Settings[:data][:connected] rescue false)
          def scheduler_loaded? = defined?(Legion::Extensions::Scheduler)

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
