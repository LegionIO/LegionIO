# frozen_string_literal: true

require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module LexDispatch
        def self.registered(app)
          register_discovery(app)
          register_dispatch(app)
        end

        # Discovery endpoints (GET)
        def self.register_discovery(app)
          # GET /api/extensions/index — list all extensions
          app.get '/api/extensions/index' do
            content_type :json
            names = Legion::API.router.extension_names
            Legion::JSON.dump({ extensions: names })
          end

          # GET /api/extensions/:lex_name/:component_type/:component_name/:method_name — full contract
          app.get '/api/extensions/:lex_name/:component_type/:component_name/:method_name' do
            content_type :json
            entry = Legion::API.router.find_extension_route(
              params[:lex_name], params[:component_type],
              params[:component_name], params[:method_name]
            )
            halt 404, Legion::JSON.dump({ error: { code: 404, message: 'route not found' } }) unless entry

            Legion::JSON.dump({
                                extension:      params[:lex_name],
                                component_type: params[:component_type],
                                component:      params[:component_name],
                                method:         params[:method_name],
                                definition:     entry[:definition],
                                hook_endpoint:  "/api/extensions/#{params[:lex_name]}/hooks/#{params[:component_name]}/#{params[:method_name]}",
                                amqp:           {
                                  exchange:    "lex.#{params[:lex_name]}",
                                  routing_key: "lex.#{params[:lex_name]}.#{params[:component_type]}.#{params[:component_name]}.#{params[:method_name]}"
                                }
                              })
          end
        end

        # Dispatch endpoint (POST)
        def self.register_dispatch(app)
          dispatcher = method(:dispatch_request)
          app.post '/api/extensions/:lex_name/:component_type/:component_name/:method_name' do
            dispatcher.call(self, request, params)
          end
        end

        def self.dispatch_request(context, request, params)
          content_type = 'application/json'
          context.content_type content_type

          entry = Legion::API.router.find_extension_route(
            params[:lex_name], params[:component_type],
            params[:component_name], params[:method_name]
          )

          unless entry
            route_key = "#{params[:lex_name]}/#{params[:component_type]}/#{params[:component_name]}/#{params[:method_name]}"
            context.halt 404, Legion::JSON.dump({
                                                  task_id:         nil,
                                                  conversation_id: nil,
                                                  status:          'failed',
                                                  error:           { code: 404, message: "no route registered for '#{route_key}'" }
                                                })
          end

          envelope = build_envelope(request)

          payload = begin
            body = request.body.read
            body.nil? || body.empty? ? {} : Legion::JSON.load(body)
          rescue StandardError
            {}
          end

          result = Legion::Ingress.run(
            payload:       payload.merge(envelope.slice(:task_id, :conversation_id, :parent_id, :master_id, :chain_id)),
            runner_class:  entry[:runner_class],
            function:      entry[:method_name].to_sym,
            source:        'lex_dispatch',
            generate_task: true
          )

          response_body = envelope.merge(
            status: result[:status],
            result: result[:result]
          ).compact

          Legion::JSON.dump(response_body)
        rescue StandardError => e
          route_key = "#{params[:lex_name]}/#{params[:component_type]}/#{params[:component_name]}/#{params[:method_name]}"
          Legion::Logging.log_exception(e, payload_summary: "LexDispatch POST #{route_key}", component_type: :api)
          context.status 500
          Legion::JSON.dump({
                              task_id:         nil,
                              conversation_id: nil,
                              status:          'failed',
                              error:           { code: 500, message: e.message }
                            })
        end

        def self.build_envelope(request)
          task_id = request.env['HTTP_X_LEGION_TASK_ID']&.to_i
          conversation_id = request.env['HTTP_X_LEGION_CONVERSATION_ID'] || ::SecureRandom.uuid
          parent_id = request.env['HTTP_X_LEGION_PARENT_ID']&.to_i
          master_id = request.env['HTTP_X_LEGION_MASTER_ID']&.to_i
          chain_id = request.env['HTTP_X_LEGION_CHAIN_ID']&.to_i
          debug = request.env['HTTP_X_LEGION_DEBUG'] == 'true'

          {
            task_id:         task_id,
            conversation_id: conversation_id,
            parent_id:       parent_id,
            master_id:       master_id || task_id,
            chain_id:        chain_id,
            debug:           debug
          }.compact
        end

        class << self
          private :register_discovery, :register_dispatch, :dispatch_request, :build_envelope
        end
      end
    end
  end
end
