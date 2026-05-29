# frozen_string_literal: true

require 'legion/cli/chat_command'

# The chat tool classes below subclass Legion::Tools::Base, and
# ExtensionToolLoader filters extension constants against it as well. On the
# `ask` / `chat prompt` client path nothing boots Legion::Service, so neither
# legion.rb nor legion/service.rb (the only files that require 'legion/tools')
# has run, leaving Legion::Tools undefined. Require it here, before the tool
# files load, or the first `require` below raises
# `uninitialized constant Legion::Tools`.
#
# legion/tools eagerly loads Tools::Do/Status/Config, which `include
# Legion::Logging::Helper` at class-definition time, so legion/logging must be
# loaded first (it defines Helper) to keep the require order safe regardless of
# how the registry is reached.
require 'legion/logging'
require 'legion/tools'

require 'legion/cli/chat/tools/read_file'
require 'legion/cli/chat/tools/write_file'
require 'legion/cli/chat/tools/edit_file'
require 'legion/cli/chat/tools/search_files'
require 'legion/cli/chat/tools/search_content'
require 'legion/cli/chat/tools/run_command'
require 'legion/cli/chat/tools/save_memory'
require 'legion/cli/chat/tools/search_memory'
require 'legion/cli/chat/tools/web_search'
require 'legion/cli/chat/tools/spawn_agent'
require 'legion/cli/chat/tools/search_traces'
require 'legion/cli/chat/tools/query_knowledge'
require 'legion/cli/chat/tools/ingest_knowledge'
require 'legion/cli/chat/tools/consolidate_memory'
require 'legion/cli/chat/tools/relate_knowledge'
require 'legion/cli/chat/tools/knowledge_maintenance'
require 'legion/cli/chat/tools/knowledge_stats'
require 'legion/cli/chat/tools/summarize_traces'
require 'legion/cli/chat/tools/list_extensions'
require 'legion/cli/chat/tools/manage_tasks'
require 'legion/cli/chat/tools/system_status'
require 'legion/cli/chat/tools/view_events'
require 'legion/cli/chat/tools/cost_summary'
require 'legion/cli/chat/tools/reflect'
require 'legion/cli/chat/tools/manage_schedules'
require 'legion/cli/chat/tools/worker_status'
require 'legion/cli/chat/tools/detect_anomalies'
require 'legion/cli/chat/tools/view_trends'
require 'legion/cli/chat/tools/trigger_dream'
require 'legion/cli/chat/tools/generate_insights'
require 'legion/cli/chat/tools/budget_status'
require 'legion/cli/chat/tools/provider_health'
require 'legion/cli/chat/tools/model_comparison'
require 'legion/cli/chat/tools/shadow_eval_status'
require 'legion/cli/chat/tools/entity_extract'
require 'legion/cli/chat/tools/arbitrage_status'
require 'legion/cli/chat/tools/escalation_status'
require 'legion/cli/chat/tools/graph_explore'
require 'legion/cli/chat/tools/scheduling_status'
require 'legion/cli/chat/tools/memory_status'

require 'legion/cli/chat/permissions'

module Legion
  module CLI
    class Chat
      module ToolRegistry
        BUILTIN_TOOLS = [
          Tools::ReadFile,
          Tools::WriteFile,
          Tools::EditFile,
          Tools::SearchFiles,
          Tools::SearchContent,
          Tools::RunCommand,
          Tools::SaveMemory,
          Tools::SearchMemory,
          Tools::WebSearch,
          Tools::SpawnAgent,
          Tools::SearchTraces,
          Tools::QueryKnowledge,
          Tools::IngestKnowledge,
          Tools::ConsolidateMemory,
          Tools::RelateKnowledge,
          Tools::KnowledgeMaintenance,
          Tools::KnowledgeStats,
          Tools::SummarizeTraces,
          Tools::ListExtensions,
          Tools::ManageTasks,
          Tools::SystemStatus,
          Tools::ViewEvents,
          Tools::CostSummary,
          Tools::Reflect,
          Tools::ManageSchedules,
          Tools::WorkerStatus,
          Tools::DetectAnomalies,
          Tools::ViewTrends,
          Tools::TriggerDream,
          Tools::GenerateInsights,
          Tools::BudgetStatus,
          Tools::ProviderHealth,
          Tools::ModelComparison,
          Tools::ShadowEvalStatus,
          Tools::EntityExtract,
          Tools::ArbitrageStatus,
          Tools::EscalationStatus,
          Tools::GraphExplore,
          Tools::SchedulingStatus,
          Tools::MemoryStatus
        ].freeze

        Permissions.apply!(BUILTIN_TOOLS)

        def self.builtin_tools
          BUILTIN_TOOLS.dup
        end

        def self.all_tools
          require 'legion/cli/chat/extension_tool_loader'
          builtin_tools + ExtensionToolLoader.discover
        rescue LoadError => e
          Legion::Logging.debug("ToolRegistry#all_tools ExtensionToolLoader not available: #{e.message}") if defined?(Legion::Logging)
          builtin_tools
        end
      end
    end
  end
end
