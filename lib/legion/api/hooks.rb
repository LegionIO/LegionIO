# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Hooks
        def self.registered(app)
          register_list(app)
          register_lex_routes(app)
        end

        def self.register_list(app)
          app.get '/api/hooks' do
            hooks = Legion::API.registered_hooks.map do |h|
              {
                lex_name: h[:lex_name], hook_name: h[:hook_name],
                hook_class: h[:hook_class].to_s, default_runner: h[:default_runner].to_s,
                route_path: h[:route_path],
                endpoint: "/api/hooks/lex/#{h[:route_path]}"
              }
            end
            json_response(hooks)
          end
        end

        def self.register_lex_routes(app)
          handler = method(:handle_hook_request)

          app.get '/api/hooks/lex/*' do
            handler.call(self, request)
          end

          app.post '/api/hooks/lex/*' do
            handler.call(self, request)
          end
        end

        def self.handle_hook_request(context, request)
          splat_path = request.path_info.sub(%r{^/api/hooks/lex/}, '')
          Legion::Logging.debug "API: #{request.request_method} /api/hooks/lex/#{splat_path}"
          hook_entry = Legion::API.find_hook_by_path(splat_path)
          if hook_entry.nil?
            Legion::Logging.warn "API #{request.request_method} #{request.path_info} returned 404: no hook registered for '#{splat_path}'"
            context.halt 404, context.json_error('not_found', "no hook registered for '#{splat_path}'", status_code: 404)
          end

          body = request.request_method == 'POST' ? request.body.read : nil
          hook = hook_entry[:hook_class].new
          unless hook.verify(request.env, body || '')
            Legion::Logging.warn "API #{request.request_method} #{request.path_info} returned 401: hook verification failed"
            context.halt 401, context.json_error('unauthorized', 'hook verification failed', status_code: 401)
          end

          payload = build_payload(request, body)
          function = hook.route(request.env, payload)
          if function.nil?
            Legion::Logging.warn "API #{request.request_method} #{request.path_info} returned 422: hook could not route this event"
            context.halt 422, context.json_error('unhandled_event', 'hook could not route this event', status_code: 422)
          end

          runner = hook.runner_class || hook_entry[:default_runner]
          if runner.nil?
            Legion::Logging.error "API #{request.request_method} #{request.path_info} returned 500: no runner class configured for hook '#{splat_path}'"
            context.halt 500, context.json_error('no_runner', 'no runner class configured for this hook', status_code: 500)
          end

          dispatch_hook(context, payload: payload, runner: runner, function: function)
        rescue StandardError => e
          Legion::Logging.log_exception(e, payload_summary: "API #{request.request_method} #{request.path_info}", component_type: :api)
          context.json_error('internal_error', e.message, status_code: 500)
        end

        def self.build_payload(request, body)
          payload = if body.nil? || body.empty?
                      request.params.transform_keys(&:to_sym)
                    else
                      Legion::JSON.load(body)
                    end
          payload[:http_method] = request.request_method
          payload[:headers] = request.env.select { |k, _| k.start_with?('HTTP_') || k == 'CONTENT_TYPE' }
          payload
        end

        def self.dispatch_hook(context, payload:, runner:, function:)
          result = Legion::Ingress.run(
            payload: payload, runner_class: runner, function: function,
            source: 'hook', check_subtask: true, generate_task: true
          )
          Legion::Logging.info "API: dispatched hook to #{runner}##{function}, task #{result[:task_id]}"
          return render_custom_response(context, result[:response]) if result.is_a?(Hash) && result[:response]

          context.json_response({ task_id: result[:task_id], status: result[:status] })
        end

        def self.render_custom_response(context, resp)
          context.status resp[:status] || 200
          context.content_type resp[:content_type] || 'application/json'
          resp[:headers]&.each { |k, v| context.headers[k] = v }
          resp[:body] || ''
        end

        class << self
          private :register_list, :register_lex_routes,
                  :handle_hook_request, :build_payload, :dispatch_hook, :render_custom_response
        end
      end
    end
  end
end
