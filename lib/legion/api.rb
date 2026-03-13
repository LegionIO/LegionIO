# frozen_string_literal: true

require 'sinatra/base'
require 'legion/json'

module Legion
  class API < Sinatra::Base
    set :show_exceptions, false
    set :raise_errors, false

    configure do
      enable :logging
    end

    # Health and readiness endpoints
    get '/health' do
      content_type :json
      Legion::JSON.dump(status: 'ok', version: Legion::VERSION)
    end

    get '/ready' do
      content_type :json
      ready = Legion::Readiness.ready?
      status ready ? 200 : 503
      Legion::JSON.dump(ready: ready, components: Legion::Readiness.to_h)
    end

    # Hook endpoints are registered dynamically as extensions load.
    # POST /hook/:lex_name           → uses the default (or only) hook
    # POST /hook/:lex_name/:hook_name → uses a specific named hook
    post '/hook/:lex_name/?:hook_name?' do
      content_type :json
      lex_name = params[:lex_name].downcase
      hook_name = params[:hook_name]&.downcase

      hook_entry = Legion::API.find_hook(lex_name, hook_name)
      halt 404, Legion::JSON.dump(error: 'no hook registered', lex: lex_name) if hook_entry.nil?

      body = request.body.read
      hook = hook_entry[:hook_class].new

      unless hook.verify(request.env, body)
        halt 401, Legion::JSON.dump(error: 'unauthorized')
      end

      payload = parse_body(body)
      function = hook.route(request.env, payload)
      halt 422, Legion::JSON.dump(error: 'unhandled event') if function.nil?

      runner = hook.runner_class || hook_entry[:default_runner]
      halt 500, Legion::JSON.dump(error: 'no runner class for hook') if runner.nil?

      result = Legion::Ingress.run(
        payload:       payload,
        runner_class:  runner,
        function:      function,
        source:        'webhook',
        check_subtask: true,
        generate_task: true
      )

      status 200
      Legion::JSON.dump(success: true, task_id: result[:task_id], status: result[:status])
    rescue StandardError => e
      Legion::Logging.error "Hook error: #{e.message}"
      Legion::Logging.error e.backtrace&.first(5)
      halt 500, Legion::JSON.dump(error: 'internal_error', message: e.message)
    end

    # Hook registry — extensions register their hooks here during autobuild
    class << self
      def hook_registry
        @hook_registry ||= {}
      end

      def register_hook(lex_name:, hook_name:, hook_class:, default_runner: nil)
        key = "#{lex_name}/#{hook_name}"
        hook_registry[key] = {
          lex_name:       lex_name,
          hook_name:      hook_name,
          hook_class:     hook_class,
          default_runner: default_runner
        }
        Legion::Logging.debug "Registered hook endpoint: POST /hook/#{key}"
      end

      def find_hook(lex_name, hook_name = nil)
        if hook_name
          hook_registry["#{lex_name}/#{hook_name}"]
        else
          # Find the default hook for this lex (first one, or one named 'webhook')
          hook_registry["#{lex_name}/webhook"] ||
            hook_registry.values.find { |h| h[:lex_name] == lex_name }
        end
      end

      def registered_hooks
        hook_registry.values
      end
    end

    private

    def parse_body(body)
      return {} if body.nil? || body.empty?

      Legion::JSON.load(body)
    rescue StandardError
      { raw: body }
    end
  end
end
