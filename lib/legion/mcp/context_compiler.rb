# frozen_string_literal: true

module Legion
  module MCP
    module ContextCompiler
      CATEGORIES = {
        tasks:         {
          tools:   %w[legion.run_task legion.list_tasks legion.get_task legion.delete_task legion.get_task_logs],
          summary: 'Create, list, query, and delete tasks. Run functions via dot-notation task identifiers.'
        },
        chains:        {
          tools:   %w[legion.list_chains legion.create_chain legion.update_chain legion.delete_chain],
          summary: 'Manage task chains - ordered sequences of tasks that execute in series.'
        },
        relationships: {
          tools:   %w[legion.list_relationships legion.create_relationship legion.update_relationship
                      legion.delete_relationship],
          summary: 'Manage trigger-action relationships between functions.'
        },
        extensions:    {
          tools:   %w[legion.list_extensions legion.get_extension legion.enable_extension
                      legion.disable_extension],
          summary: 'Manage LEX extensions - list installed, inspect details, enable/disable.'
        },
        schedules:     {
          tools:   %w[legion.list_schedules legion.create_schedule legion.update_schedule legion.delete_schedule],
          summary: 'Manage scheduled tasks - cron-style recurring task execution.'
        },
        workers:       {
          tools:   %w[legion.list_workers legion.show_worker legion.worker_lifecycle legion.worker_costs],
          summary: 'Manage digital workers - list, inspect, lifecycle transitions, cost tracking.'
        },
        rbac:          {
          tools:   %w[legion.rbac_check legion.rbac_assignments legion.rbac_grants],
          summary: 'Role-based access control - check permissions, view assignments and grants.'
        },
        status:        {
          tools:   %w[legion.get_status legion.get_config legion.team_summary legion.routing_stats],
          summary: 'System status, configuration, team overview, and routing statistics.'
        },
        describe:      {
          tools:   %w[legion.describe_runner],
          summary: 'Inspect a specific runner function - parameters, return type, metadata.'
        }
      }.freeze

      module_function

      # Returns a compressed summary of all categories with tool counts and tool name lists.
      # @return [Array<Hash>] array of { category:, summary:, tool_count:, tools: }
      def compressed_catalog
        CATEGORIES.map do |category, config|
          tool_names = config[:tools]
          {
            category:   category,
            summary:    config[:summary],
            tool_count: tool_names.length,
            tools:      tool_names
          }
        end
      end

      # Returns tools for a specific category, filtered to only those present in TOOL_CLASSES.
      # @param category_sym [Symbol] one of the CATEGORIES keys
      # @return [Hash, nil] { category:, summary:, tools: [{ name:, description:, params: }] } or nil
      def category_tools(category_sym)
        config = CATEGORIES[category_sym]
        return nil unless config

        index = tool_index
        tools = config[:tools].filter_map { |name| index[name] }
        return nil if tools.empty?

        {
          category: category_sym,
          summary:  config[:summary],
          tools:    tools
        }
      end

      # Keyword-match intent against tool names and descriptions.
      # @param intent_string [String] natural language intent
      # @return [Class, nil] best matching tool CLASS from Server::TOOL_CLASSES or nil
      def match_tool(intent_string)
        scored = scored_tools(intent_string)
        return nil if scored.empty?

        best = scored.max_by { |entry| entry[:score] }
        return nil if best[:score].zero?

        Server::TOOL_CLASSES.find { |klass| klass.tool_name == best[:name] }
      end

      # Returns top N keyword-matched tools ranked by score.
      # @param intent_string [String] natural language intent
      # @param limit [Integer] max results (default 5)
      # @return [Array<Hash>] array of { name:, description:, score: }
      def match_tools(intent_string, limit: 5)
        scored = scored_tools(intent_string)
                 .select { |entry| entry[:score].positive? }
                 .sort_by { |entry| -entry[:score] }
        scored.first(limit)
      end

      # Returns a hash keyed by tool_name with compressed param info.
      # Memoized — call reset! to clear.
      # @return [Hash<String, Hash>] { name:, description:, params: [String] }
      def tool_index
        @tool_index ||= build_tool_index
      end

      # Clears the memoized tool_index.
      def reset!
        @tool_index = nil
      end

      def build_tool_index
        Server::TOOL_CLASSES.each_with_object({}) do |klass, idx|
          raw_schema = klass.input_schema
          schema = raw_schema.is_a?(Hash) ? raw_schema : raw_schema.to_h
          properties = schema[:properties] || {}
          idx[klass.tool_name] = {
            name:        klass.tool_name,
            description: klass.description,
            params:      properties.keys.map(&:to_s)
          }
        end
      end

      def scored_tools(intent_string)
        keywords = intent_string.downcase.split
        return [] if keywords.empty?

        tool_index.values.map do |entry|
          haystack = "#{entry[:name].downcase} #{entry[:description].downcase}"
          score    = keywords.count { |kw| haystack.include?(kw) }
          { name: entry[:name], description: entry[:description], score: score }
        end
      end
    end
  end
end
