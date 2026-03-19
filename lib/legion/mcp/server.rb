# frozen_string_literal: true

require_relative 'observer'
require_relative 'usage_filter'
require_relative 'tools/run_task'
require_relative 'tools/describe_runner'
require_relative 'tools/list_tasks'
require_relative 'tools/get_task'
require_relative 'tools/delete_task'
require_relative 'tools/get_task_logs'
require_relative 'tools/list_chains'
require_relative 'tools/create_chain'
require_relative 'tools/update_chain'
require_relative 'tools/delete_chain'
require_relative 'tools/list_relationships'
require_relative 'tools/create_relationship'
require_relative 'tools/update_relationship'
require_relative 'tools/delete_relationship'
require_relative 'tools/list_extensions'
require_relative 'tools/get_extension'
require_relative 'tools/enable_extension'
require_relative 'tools/disable_extension'
require_relative 'tools/list_schedules'
require_relative 'tools/create_schedule'
require_relative 'tools/update_schedule'
require_relative 'tools/delete_schedule'
require_relative 'tools/get_status'
require_relative 'tools/get_config'
require_relative 'tools/list_workers'
require_relative 'tools/show_worker'
require_relative 'tools/worker_lifecycle'
require_relative 'tools/worker_costs'
require_relative 'tools/team_summary'
require_relative 'tools/routing_stats'
require_relative 'tools/rbac_check'
require_relative 'tools/rbac_assignments'
require_relative 'tools/rbac_grants'
require_relative 'context_compiler'
require_relative 'embedding_index'
require_relative 'tools/do_action'
require_relative 'tools/discover_tools'
require_relative 'resources/runner_catalog'
require_relative 'resources/extension_info'

module Legion
  module MCP
    module Server
      TOOL_CLASSES = [
        Tools::RunTask,
        Tools::DescribeRunner,
        Tools::ListTasks,
        Tools::GetTask,
        Tools::DeleteTask,
        Tools::GetTaskLogs,
        Tools::ListChains,
        Tools::CreateChain,
        Tools::UpdateChain,
        Tools::DeleteChain,
        Tools::ListRelationships,
        Tools::CreateRelationship,
        Tools::UpdateRelationship,
        Tools::DeleteRelationship,
        Tools::ListExtensions,
        Tools::GetExtension,
        Tools::EnableExtension,
        Tools::DisableExtension,
        Tools::ListSchedules,
        Tools::CreateSchedule,
        Tools::UpdateSchedule,
        Tools::DeleteSchedule,
        Tools::GetStatus,
        Tools::GetConfig,
        Tools::ListWorkers,
        Tools::ShowWorker,
        Tools::WorkerLifecycle,
        Tools::WorkerCosts,
        Tools::TeamSummary,
        Tools::RoutingStats,
        Tools::RbacCheck,
        Tools::RbacAssignments,
        Tools::RbacGrants,
        Tools::DoAction,
        Tools::DiscoverTools
      ].freeze

      class << self
        def build(identity: nil)
          tools = if ToolGovernance.governance_enabled?
                    ToolGovernance.filter_tools(TOOL_CLASSES, identity)
                  else
                    TOOL_CLASSES
                  end

          server = ::MCP::Server.new(
            name:               'legion',
            version:            Legion::VERSION,
            instructions:       instructions,
            tools:              tools,
            resources:          Resources::ExtensionInfo.static_resources,
            resource_templates: Resources::ExtensionInfo.resource_templates
          )

          if defined?(Observer)
            ::MCP.configure do |c|
              c.instrumentation_callback = ->(idata) { Server.wire_observer(idata) }
            end
          end

          server.tools_list_handler do |_params|
            build_filtered_tool_list.map(&:to_h)
          end

          # Populate embedding index for semantic tool matching (lazy — no-op if LLM unavailable)
          populate_embedding_index

          Resources::RunnerCatalog.register(server)
          Resources::ExtensionInfo.register_read_handler(server)

          server
        end

        def populate_embedding_index(embedder: EmbeddingIndex.default_embedder)
          return unless embedder

          tool_data = ContextCompiler.tool_index.values
          EmbeddingIndex.build_from_tool_data(tool_data, embedder: embedder)
        end

        def wire_observer(data)
          return unless data[:method] == 'tools/call' && data[:tool_name]

          duration_ms = (data[:duration].to_f * 1000).to_i
          params_keys = data[:tool_arguments].respond_to?(:keys) ? data[:tool_arguments].keys : []
          success     = data[:error].nil?

          Observer.record(
            tool_name:   data[:tool_name],
            duration_ms: duration_ms,
            success:     success,
            params_keys: params_keys,
            error:       data[:error]
          )
        end

        def build_filtered_tool_list(keywords: [])
          tool_names = TOOL_CLASSES.map { |tc| tc.respond_to?(:tool_name) ? tc.tool_name : tc.name }
          ranked     = UsageFilter.ranked_tools(tool_names, keywords: keywords)
          ranked.filter_map { |name| TOOL_CLASSES.find { |tc| (tc.respond_to?(:tool_name) ? tc.tool_name : tc.name) == name } }
        end

        private

        def instructions
          <<~TEXT
            Legion is an async job engine. You can run tasks, create chains and relationships between services, manage extensions, and query system status.

            Use `legion.run_task` with dot notation (e.g., "http.request.get") for quick task execution.
            Use `legion.describe_runner` to discover available functions on a runner.
            CRUD tools follow the pattern: legion.list_*, legion.create_*, legion.get_*, legion.update_*, legion.delete_*.
          TEXT
        end
      end
    end
  end
end
