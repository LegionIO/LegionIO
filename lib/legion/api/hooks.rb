# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Hooks
        def self.registered(app)
          register_list(app)
          register_trigger(app)
        end

        def self.register_list(app)
          app.get '/api/hooks' do
            hooks = Legion::API.registered_hooks.map do |h|
              {
                lex_name: h[:lex_name], hook_name: h[:hook_name],
                hook_class: h[:hook_class].to_s, default_runner: h[:default_runner].to_s,
                endpoint: "/api/hooks/#{h[:lex_name]}/#{h[:hook_name]}"
              }
            end
            json_response(hooks)
          end
        end

        def self.register_trigger(app)
          app.post '/api/hooks/:lex_name/?:hook_name?' do
            content_type :json
            lex_name = params[:lex_name].downcase
            hook_name = params[:hook_name]&.downcase

            hook_entry = Legion::API.find_hook(lex_name, hook_name)
            halt 404, json_error('not_found', "no hook registered for '#{lex_name}'", status_code: 404) if hook_entry.nil?

            body = request.body.read
            hook = hook_entry[:hook_class].new

            halt 401, json_error('unauthorized', 'hook verification failed', status_code: 401) unless hook.verify(request.env, body)

            payload = body.nil? || body.empty? ? {} : Legion::JSON.load(body)
            function = hook.route(request.env, payload)
            halt 422, json_error('unhandled_event', 'hook could not route this event', status_code: 422) if function.nil?

            runner = hook.runner_class || hook_entry[:default_runner]
            halt 500, json_error('no_runner', 'no runner class configured for this hook', status_code: 500) if runner.nil?

            result = Legion::Ingress.run(
              payload: payload, runner_class: runner, function: function,
              source: 'webhook', check_subtask: true, generate_task: true
            )

            json_response({ task_id: result[:task_id], status: result[:status] })
          rescue StandardError => e
            Legion::Logging.error "Hook error: #{e.message}"
            Legion::Logging.error e.backtrace&.first(5)
            json_error('internal_error', e.message, status_code: 500)
          end
        end

        class << self
          private :register_list, :register_trigger
        end
      end
    end
  end
end
