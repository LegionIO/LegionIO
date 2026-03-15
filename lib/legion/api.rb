# frozen_string_literal: true

require 'sinatra/base'
require 'legion/json'
require_relative 'events'
require_relative 'readiness'

require_relative 'api/middleware/auth'
require_relative 'api/helpers'
require_relative 'api/tasks'
require_relative 'api/extensions'
require_relative 'api/nodes'
require_relative 'api/schedules'
require_relative 'api/relationships'
require_relative 'api/chains'
require_relative 'api/settings'
require_relative 'api/events'
require_relative 'api/transport'
require_relative 'api/hooks'
require_relative 'api/workers'
require_relative 'api/coldstart'
require_relative 'api/gaia'

module Legion
  class API < Sinatra::Base
    helpers Legion::API::Helpers

    set :show_exceptions, false
    set :raise_errors, false

    configure do
      enable :logging
      set :host_authorization, permitted: :any
    end

    # Health and readiness
    get '/api/health' do
      json_response({ status: 'ok', version: Legion::VERSION })
    end

    get '/api/ready' do
      ready = Legion::Readiness.ready?
      json_response({ ready: ready, components: Legion::Readiness.to_h }, status_code: ready ? 200 : 503)
    end

    # Global error handlers
    not_found do
      content_type :json
      Legion::JSON.dump({
                          error: { code: 'not_found', message: "no route matches #{request.request_method} #{request.path_info}" },
                          meta:  { timestamp: Time.now.utc.iso8601, node: Legion::Settings[:client][:name] }
                        })
    end

    error do
      content_type :json
      err = env['sinatra.error']
      Legion::Logging.error "Unhandled API error: #{err.message}"
      Legion::Logging.error err.backtrace&.first(10)
      Legion::JSON.dump({
                          error: { code: 'internal_error', message: err.message },
                          meta:  { timestamp: Time.now.utc.iso8601, node: Legion::Settings[:client][:name] }
                        })
    end

    # Mount route modules
    register Routes::Tasks
    register Routes::Extensions
    register Routes::Nodes
    register Routes::Schedules
    register Routes::Relationships
    register Routes::Chains
    register Routes::Settings
    register Routes::Events
    register Routes::Transport
    register Routes::Hooks
    register Routes::Workers
    register Routes::Coldstart
    register Routes::Gaia

    # Hook registry (preserved from original implementation)
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
        Legion::Logging.debug "Registered hook endpoint: POST /api/hooks/#{key}"
      end

      def find_hook(lex_name, hook_name = nil)
        if hook_name
          hook_registry["#{lex_name}/#{hook_name}"]
        else
          hook_registry["#{lex_name}/webhook"] ||
            hook_registry.values.find { |h| h[:lex_name] == lex_name }
        end
      end

      def registered_hooks
        hook_registry.values
      end
    end
  end
end
