# frozen_string_literal: true

require 'sinatra/base'
require 'legion/json'
require_relative 'events'
require_relative 'readiness'

require_relative 'api/middleware/auth'
require_relative 'api/middleware/body_limit'
require_relative 'api/middleware/rate_limit'
require_relative 'api/middleware/request_logger'
require_relative 'api/helpers'
require_relative 'api/validators'
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
require_relative 'api/lex'
require_relative 'api/workers'
require_relative 'api/coldstart'
require_relative 'api/gaia'
require_relative 'api/openapi'
require_relative 'api/rbac'
require_relative 'api/auth'
require_relative 'api/auth_worker'
require_relative 'api/auth_human'
require_relative 'api/auth_saml'
require_relative 'api/capacity'
require_relative 'api/audit'
require_relative 'api/metrics'
require_relative 'api/llm'
require_relative 'api/catalog'
require_relative 'api/org_chart'
require_relative 'api/workflow'
require_relative 'api/governance'
require_relative 'api/acp'
require_relative 'api/prompts'
require_relative 'api/marketplace'
require_relative 'api/apollo'
require_relative 'api/graphql' if defined?(GraphQL)

module Legion
  class API < Sinatra::Base
    helpers Legion::API::Helpers
    helpers Legion::API::Validators

    set :show_exceptions, false
    set :raise_errors, false
    set :public_folder, File.expand_path('../../public', __dir__)
    set :static, true

    configure do
      set :logging, nil
      set :quiet, true
      set :logger, Legion::Logging.log if Legion.const_defined?(:Logging)
      set :host_authorization, permitted: :any
    end

    # OpenAPI spec (no auth required)
    get '/api/openapi.json' do
      content_type :json
      Legion::API::OpenAPI.to_json
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
      Legion::Logging.warn "API #{request.request_method} #{request.path_info} returned 404: no route matches"
      Legion::JSON.dump({
                          error: { code: 'not_found', message: "no route matches #{request.request_method} #{request.path_info}" },
                          meta:  { timestamp: Time.now.utc.iso8601, node: Legion::Settings[:client][:name] }
                        })
    end

    error do
      content_type :json
      err = env['sinatra.error']
      Legion::Logging.error "API #{request.request_method} #{request.path_info} returned 500: #{err.class} — #{err.message}"
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
    register Routes::Workflow
    register Routes::Relationships
    register Routes::Chains
    register Routes::Settings
    register Routes::Events
    register Routes::Transport
    register Routes::Hooks
    register Routes::Lex
    register Routes::Workers
    register Routes::Coldstart
    register Routes::Gaia
    register Routes::Rbac
    register Routes::Auth
    register Routes::AuthWorker
    register Routes::AuthHuman
    register Routes::AuthSaml
    register Routes::Capacity
    register Routes::Audit
    register Routes::Metrics
    register Routes::Llm
    register Routes::ExtensionCatalog
    register Routes::OrgChart
    register Routes::Governance
    register Routes::Acp
    register Routes::Prompts
    register Routes::Marketplace
    register Routes::Apollo
    register Routes::GraphQL if defined?(Routes::GraphQL)

    use Legion::API::Middleware::RequestLogger
    use Legion::Rbac::Middleware if defined?(Legion::Rbac::Middleware)

    # Hook registry (preserved from original implementation)
    class << self
      def hook_registry
        @hook_registry ||= {}
      end

      def register_hook(lex_name:, hook_name:, hook_class:, default_runner: nil, route_path: nil)
        route = route_path || "#{lex_name}/#{hook_name}"
        key = route
        hook_registry[key] = {
          lex_name:       lex_name,
          hook_name:      hook_name,
          hook_class:     hook_class,
          default_runner: default_runner,
          route_path:     route
        }
        Legion::Logging.debug "Registered hook endpoint: /api/hooks/lex/#{route}"
      end

      def find_hook(lex_name, hook_name = nil)
        if hook_name
          hook_registry["#{lex_name}/#{hook_name}"]
        else
          hook_registry["#{lex_name}/webhook"] ||
            hook_registry.values.find { |h| h[:lex_name] == lex_name }
        end
      end

      def find_hook_by_path(path)
        hook_registry[path] || hook_registry.values.find { |h| h[:route_path] == path }
      end

      def registered_hooks
        hook_registry.values
      end

      def route_registry
        @route_registry ||= {}
      end

      def register_route(lex_name:, runner_name:, function:, runner_class:, route_path:)
        route_registry[route_path] = {
          lex_name:     lex_name,
          runner_name:  runner_name,
          function:     function,
          runner_class: runner_class,
          route_path:   route_path
        }
        Legion::Logging.debug "Registered LEX route: POST /api/lex/#{route_path}"
      end

      def find_route_by_path(path)
        route_registry[path]
      end

      def registered_routes
        route_registry.values
      end
    end
  end
end
