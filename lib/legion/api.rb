# frozen_string_literal: true

require 'sinatra/base'
require 'legion/json'
require_relative 'events'
require_relative 'readiness'
require_relative 'api/default_settings'

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
require_relative 'api/workers'
require_relative 'api/coldstart'
require_relative 'api/gaia'
require_relative 'api/openapi'
require_relative 'api/rbac'
require_relative 'api/auth'
require_relative 'api/auth_teams'
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
require_relative 'api/costs'
require_relative 'api/traces'
require_relative 'api/stats'
require_relative 'api/absorbers'
require_relative 'api/codegen'
require_relative 'api/knowledge'
require_relative 'api/mesh'
require_relative 'api/metering'
require_relative 'api/logs'
require_relative 'api/router'
require_relative 'api/library_routes'
require_relative 'api/sync_dispatch'
require_relative 'api/lex_dispatch'
require_relative 'api/tbi_patterns'
require_relative 'api/webhooks'
require_relative 'api/tenants'
require_relative 'api/inbound_webhooks'
require_relative 'api/identity_audit'
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

    # Root discovery — lists all tiers
    get '/api/discovery' do
      content_type :json
      Legion::JSON.dump({
                          infrastructure: [
                            { path: '/api/health', method: 'GET' },
                            { path: '/api/ready', method: 'GET' },
                            { path: '/api/openapi.json', method: 'GET' },
                            { path: '/api/discovery', method: 'GET' }
                          ],
                          libraries:      Legion::API.router.library_names,
                          extensions:     Legion::API.router.extension_names
                        })
    end

    # Health and readiness
    get '/api/health' do
      json_response({ status: 'ok', version: Legion::VERSION })
    end

    get '/api/ready' do
      ready = Legion::Readiness.ready?
      json_response({ ready: ready, components: Legion::Readiness.to_h }, status_code: ready ? 200 : 503)
    end

    post '/api/reload' do
      log.error "[api] reload attempted by #{request.ip} — blocked"
      halt 418, { 'Content-Type' => 'application/json' },
           Legion::JSON.dump({ error: 'reload is disabled', status: 418 })
    end

    # Global error handlers
    not_found do
      content_type :json
      Legion::Logging.warn "API #{request.request_method} #{request.path_info} returned 404: no route matches"
      Legion::JSON.dump({
                          task_id:         nil,
                          conversation_id: nil,
                          status:          'failed',
                          error:           {
                            code:    404,
                            message: "no route matches #{request.request_method} #{request.path_info}"
                          },
                          meta:            { timestamp: Time.now.utc.iso8601, node: Legion::Settings[:client][:name] }
                        })
    end

    error do
      content_type :json
      err = env['sinatra.error']
      Legion::Logging.log_exception(err, payload_summary: "API #{request.request_method} #{request.path_info} returned 500", component_type: :api)
      Legion::JSON.dump({
                          task_id:         nil,
                          conversation_id: nil,
                          status:          'failed',
                          error:           { code: 500, message: err.message },
                          meta:            { timestamp: Time.now.utc.iso8601, node: Legion::Settings[:client][:name] }
                        })
    end

    # Tier-aware router (three-tier namespace)
    class << self
      def router
        @router ||= Legion::API::Router.new
      end

      def mount_library_routes(gem_name, fallback_module, preferred_constant_path)
        preferred = constant_from_path(preferred_constant_path)
        if preferred.is_a?(Module)
          register_library_routes(gem_name, preferred)
        elsif router.library_names.include?(gem_name)
          register_library_routes(gem_name, router.library_routes.fetch(gem_name))
        else
          register fallback_module
        end
      end

      private

      def constant_from_path(path)
        path.to_s.split('::').reject(&:empty?).reduce(Object) { |scope, name| scope.const_get(name) }
      rescue NameError
        nil
      end
    end

    # Mount route modules
    register Routes::LexDispatch
    register Routes::Tasks
    register Routes::Extensions
    register Routes::Nodes
    register Routes::Schedules
    register Routes::Workflow
    register Routes::Relationships
    register Routes::Chains
    register Routes::Settings
    register Routes::Events
    register Routes::Transport unless router.library_names.include?('transport')
    register Routes::Workers
    register Routes::Coldstart
    register Routes::Gaia unless router.library_names.include?('gaia')
    register Routes::Rbac unless router.library_names.include?('rbac')
    register Routes::Auth
    register Routes::AuthTeams
    register Routes::AuthWorker
    register Routes::AuthHuman
    register Routes::AuthSaml
    register Routes::Capacity
    register Routes::Audit
    register Routes::Metrics
    mount_library_routes('llm', Routes::Llm, 'Legion::LLM::Routes')
    register Routes::ExtensionCatalog
    register Routes::OrgChart
    register Routes::Governance
    register Routes::Acp
    register Routes::Prompts
    register Routes::Marketplace
    mount_library_routes('apollo', Routes::Apollo, 'Legion::Apollo::Routes')
    register Routes::Costs
    register Routes::Traces
    register Routes::Stats
    register Routes::Absorbers
    register Routes::Codegen
    register Routes::Knowledge
    register Routes::Mesh
    register Routes::Metering
    register Routes::Logs
    register Routes::TbiPatterns
    register Routes::Webhooks
    register Routes::Tenants
    register Routes::InboundWebhooks
    register Routes::IdentityAudit
    register Routes::GraphQL if defined?(Routes::GraphQL)

    use Legion::API::Middleware::RequestLogger
    use Legion::Rbac::Middleware if defined?(Legion::Rbac::Middleware)
    use ElasticAPM::Middleware if defined?(ElasticAPM::Middleware) &&
                                  Legion::Settings.dig(:api, :elastic_apm, :enabled)
  end
end
