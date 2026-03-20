# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Acp
        def self.registered(app)
          app.get '/.well-known/agent.json' do
            card = build_agent_card
            content_type :json
            Legion::JSON.dump(card)
          end

          app.post '/api/acp/tasks' do
            body = parse_request_body
            payload = (body[:input] || {}).transform_keys(&:to_sym)

            result = Legion::Ingress.run(
              payload:      payload,
              runner_class: body[:runner_class],
              function:     body[:function],
              source:       'acp'
            )

            json_response({ task_id: result[:task_id], status: 'queued' }, status_code: 202)
          end

          app.get '/api/acp/tasks/:id' do
            task = find_task(params[:id])
            halt 404, json_error(404, 'Task not found') unless task

            json_response({
                            task_id:      task[:id],
                            status:       translate_status(task[:status]),
                            output:       { data: task[:result] },
                            created_at:   task[:created_at]&.to_s,
                            completed_at: task[:completed_at]&.to_s
                          })
          end

          app.delete '/api/acp/tasks/:id' do
            halt 501, json_error(501, 'Task cancellation not implemented')
          end
        end
      end
    end

    helpers do
      def build_agent_card
        name = begin
          Legion::Settings[:client][:name]
        rescue StandardError
          'legion'
        end
        port = begin
          settings.port || 4567
        rescue StandardError
          4567
        end
        {
          name:               name,
          description:        'LegionIO digital worker',
          url:                "http://#{request.host}:#{port}/api/acp",
          version:            '2.0',
          protocol:           'acp/1.0',
          capabilities:       discover_capabilities,
          authentication:     { schemes: ['bearer'] },
          defaultInputModes:  ['text/plain', 'application/json'],
          defaultOutputModes: ['text/plain', 'application/json']
        }
      end

      def discover_capabilities
        if defined?(Legion::Extensions::Mesh::Helpers::Registry)
          Legion::Extensions::Mesh::Helpers::Registry.new.capabilities.keys.map(&:to_s)
        else
          []
        end
      rescue StandardError
        []
      end

      def find_task(id)
        return nil unless defined?(Legion::Data)

        Legion::Data::Model::Task[id.to_i]&.values
      rescue StandardError
        nil
      end

      def translate_status(status)
        case status&.to_s
        when /completed/ then 'completed'
        when /exception|failed/ then 'failed'
        when /queued|scheduled/ then 'queued'
        else 'in_progress'
        end
      end
    end
  end
end
