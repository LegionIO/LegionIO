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
            unless entry
              halt 404, Legion::JSON.dump({
                                            task_id:         nil,
                                            conversation_id: nil,
                                            status:          'failed',
                                            error:           { code: 404, message: 'route not found' }
                                          })
            end

            amqp_pfx = entry[:amqp_prefix].to_s.then { |p| p.empty? ? "lex.#{params[:lex_name]}" : p }
            response = {
              extension:      params[:lex_name],
              component_type: params[:component_type],
              component:      params[:component_name],
              method:         params[:method_name],
              definition:     entry[:definition],
              amqp:           {
                exchange:    amqp_pfx,
                routing_key: "#{amqp_pfx}.#{params[:component_type]}.#{params[:component_name]}.#{params[:method_name]}"
              }
            }
            if params[:component_type] == 'hooks'
              response[:hook_endpoint] =
                "/api/extensions/#{params[:lex_name]}/hooks/#{params[:component_name]}/#{params[:method_name]}"
            end
            Legion::JSON.dump(response)
          end
        end

        # Dispatch endpoint (POST)
        def self.register_dispatch(app)
          dispatcher = method(:dispatch_request)
          app.post '/api/extensions/:lex_name/:component_type/:component_name/:method_name' do
            dispatcher.call(self, request, params)
          end
        end

        def self.dispatch_request(context, request, params) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
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
          rescue StandardError => e
            Legion::Logging.warn "[LexDispatch] invalid JSON body: #{e.message}" if defined?(Legion::Logging)
            context.halt 400, Legion::JSON.dump({
                                                  task_id:         nil,
                                                  conversation_id: nil,
                                                  status:          'failed',
                                                  error:           { code: 400, message: 'request body is not valid JSON' }
                                                })
          end

          # Remote dispatch: when the runner class is not loaded locally, forward via AMQP
          unless extension_loaded_locally?(entry)
            if definition_blocks_remote?(entry)
              context.halt 403, Legion::JSON.dump({
                                                    task_id:         nil,
                                                    conversation_id: nil,
                                                    status:          'failed',
                                                    error:           { code: 403, message: 'Method not remotely invocable' }
                                                  })
            end

            exchange_name = entry[:amqp_prefix].to_s.then { |p| p.empty? ? "lex.#{entry[:lex_name]}" : p }
            routing_key   = "#{exchange_name}.#{entry[:component_type]}.#{entry[:component_name]}.#{entry[:method_name]}"

            if request.env['HTTP_X_LEGION_SYNC'] == 'true'
              result = Legion::API::SyncDispatch.dispatch(exchange_name, routing_key, payload, envelope)
              return Legion::JSON.dump(result)
            else
              unless defined?(Legion::Transport) &&
                     Legion::Transport.respond_to?(:connected?) &&
                     Legion::Transport.connected?
                context.halt 503, Legion::JSON.dump({
                                                      task_id:         nil,
                                                      conversation_id: nil,
                                                      status:          'failed',
                                                      error:           { code: 503, message: 'Transport not available' }
                                                    })
              end

              dispatch_async_amqp(exchange_name, routing_key, payload, envelope)
              context.status 202
              return Legion::JSON.dump(envelope.merge(status: 'queued'))
            end
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

        def self.parse_header_integer(value)
          return nil if value.nil?

          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end

        def self.build_envelope(request)
          task_id         = parse_header_integer(request.env['HTTP_X_LEGION_TASK_ID'])
          conversation_id = request.env['HTTP_X_LEGION_CONVERSATION_ID'] || ::SecureRandom.uuid
          parent_id       = parse_header_integer(request.env['HTTP_X_LEGION_PARENT_ID'])
          master_id       = parse_header_integer(request.env['HTTP_X_LEGION_MASTER_ID'])
          chain_id        = parse_header_integer(request.env['HTTP_X_LEGION_CHAIN_ID'])
          debug           = request.env['HTTP_X_LEGION_DEBUG'] == 'true'

          {
            task_id:         task_id,
            conversation_id: conversation_id,
            parent_id:       parent_id,
            master_id:       master_id || task_id,
            chain_id:        chain_id,
            debug:           debug
          }.compact
        end

        # Returns true when the runner class referenced by the route entry is
        # available in the current process (i.e. the extension is loaded locally).
        def self.extension_loaded_locally?(entry)
          runner_class = entry[:runner_class]
          return false if runner_class.nil? || runner_class.to_s.empty?

          # Try constant lookup — safe because runner_class is from the route registry,
          # not from user input.
          parts = runner_class.to_s.split('::').reject(&:empty?)
          parts.reduce(Object) { |mod, name| mod.const_get(name, false) }
          true
        rescue NameError, TypeError
          false
        end

        # Returns true when the definition-level flag explicitly disables remote dispatch.
        # Extension-level gate (entry[:lex_name] module) takes precedence over definition flag.
        def self.definition_blocks_remote?(entry)
          defn = entry[:definition]
          return false if defn.nil?

          defn[:remote_invocable] == false
        end

        # Publish an async AMQP message for remote dispatch (fire-and-forget).
        def self.dispatch_async_amqp(exchange_name, routing_key, payload, envelope)
          return unless defined?(Legion::Transport) &&
                        Legion::Transport.respond_to?(:connected?) &&
                        Legion::Transport.connected?

          channel = Legion::Transport.channel
          exchange = channel.exchange(exchange_name, type: :topic, durable: true, passive: true)
          message = Legion::JSON.dump(payload.merge(envelope))
          exchange.publish(message, routing_key: routing_key, content_type: 'application/json', persistent: true)
        rescue StandardError => e
          Legion::Logging.warn "[LexDispatch] async AMQP publish failed: #{e.message}" if defined?(Legion::Logging)
          raise
        end

        class << self
          private :register_discovery, :register_dispatch, :dispatch_request, :parse_header_integer,
                  :build_envelope, :extension_loaded_locally?, :definition_blocks_remote?, :dispatch_async_amqp
        end
      end
    end
  end
end
