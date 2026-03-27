# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Lex
        def self.registered(app)
          register_list(app)
          register_lex_routes(app)
        end

        def self.register_list(app)
          app.get '/api/lex' do
            routes = Legion::API.registered_routes.map do |r|
              {
                endpoint:     "/api/lex/#{r[:route_path]}",
                extension:    r[:lex_name],
                runner:       r[:runner_name],
                function:     r[:function],
                runner_class: r[:runner_class]
              }
            end
            json_response(routes)
          end
        end

        def self.register_lex_routes(app)
          handler = method(:handle_lex_request)
          app.post '/api/lex/*' do
            handler.call(self, request)
          end
        end

        def self.handle_lex_request(context, request)
          splat_path = request.path_info.sub(%r{^/api/lex/}, '')
          Legion::Logging.debug "API: POST /api/lex/#{splat_path}"
          route_entry = Legion::API.find_route_by_path(splat_path)
          if route_entry.nil?
            Legion::Logging.warn "API POST /api/lex/#{splat_path} returned 404: no route registered"
            context.halt 404, context.json_error('route_not_found',
                                                 "no route registered for '#{splat_path}'", status_code: 404)
          end

          payload = build_payload(request)
          result = Legion::Ingress.run(
            payload:       payload,
            runner_class:  route_entry[:runner_class],
            function:      route_entry[:function],
            source:        'lex_route',
            generate_task: true
          )
          Legion::Logging.info "API: LEX route #{splat_path} dispatched to #{route_entry[:runner_class]}, task #{result[:task_id]}"
          context.json_response({ task_id: result[:task_id], status: result[:status],
                                   result: result[:result] }.compact)
        rescue StandardError => e
          Legion::Logging.log_exception(e, payload_summary: "API POST /api/lex/#{request.path_info.sub(%r{^/api/lex/}, '')}", component_type: :api)
          context.json_error('internal_error', e.message, status_code: 500)
        end

        def self.build_payload(request)
          body = request.body.read
          payload = if body.nil? || body.empty?
                      {}
                    else
                      Legion::JSON.load(body)
                    end
          payload[:http_method] = request.request_method
          payload[:headers] = request.env.select { |k, _| k.start_with?('HTTP_') || k == 'CONTENT_TYPE' }
          payload
        end

        class << self
          private :register_list, :register_lex_routes, :handle_lex_request, :build_payload
        end
      end
    end
  end
end
