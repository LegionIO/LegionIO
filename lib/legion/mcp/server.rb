# frozen_string_literal: true

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
        Tools::RoutingStats
      ].freeze

      class << self
        def build
          server = ::MCP::Server.new(
            name:               'legion',
            version:            Legion::VERSION,
            instructions:       instructions,
            tools:              TOOL_CLASSES,
            resources:          Resources::ExtensionInfo.static_resources,
            resource_templates: Resources::ExtensionInfo.resource_templates
          )

          Resources::RunnerCatalog.register(server)
          Resources::ExtensionInfo.register_read_handler(server)

          server
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
