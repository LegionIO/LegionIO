# frozen_string_literal: true

module Legion
  module MCP
    module UsageFilter
      ESSENTIAL_TOOLS = %w[
        legion.do legion.tools legion.run_task legion.get_status legion.describe_runner
      ].freeze

      FREQUENCY_WEIGHT = 0.5
      RECENCY_WEIGHT   = 0.3
      KEYWORD_WEIGHT   = 0.2
      BASELINE_SCORE   = 0.1

      module_function

      def score_tools(tool_names, keywords: [])
        all_stats = Observer.all_tool_stats
        call_counts = tool_names.map { |n| all_stats.dig(n, :call_count) || 0 }
        max_calls   = call_counts.max || 0

        tool_names.each_with_object({}) do |name, hash|
          stats = all_stats[name]

          freq_score = if max_calls.positive? && stats
                         (stats[:call_count].to_f / max_calls) * FREQUENCY_WEIGHT
                       else
                         0.0
                       end

          rec_score = if stats&.dig(:last_used)
                        recency_decay(stats[:last_used]) * RECENCY_WEIGHT
                      else
                        0.0
                      end

          kw_score = keyword_match(name, keywords) * KEYWORD_WEIGHT

          total = freq_score + rec_score + kw_score
          total = BASELINE_SCORE if total.zero?

          hash[name] = total.round(6)
        end
      end

      def ranked_tools(tool_names, limit: nil, keywords: [])
        scores = score_tools(tool_names, keywords: keywords)
        ranked = tool_names.sort_by { |n| -scores.fetch(n, BASELINE_SCORE) }
        limit ? ranked.first(limit) : ranked
      end

      def prune_dead_tools(tool_names, prune_after_seconds: 86_400 * 30)
        stats = Observer.stats
        window = stats[:since]
        elapsed = window ? (Time.now - window) : 0

        return tool_names if elapsed < prune_after_seconds

        all_stats = Observer.all_tool_stats
        tool_names.reject do |name|
          next false if ESSENTIAL_TOOLS.include?(name)

          calls = all_stats.dig(name, :call_count) || 0
          calls.zero?
        end
      end

      def recency_decay(last_used)
        return 0.0 unless last_used

        age_seconds = Time.now - last_used
        return 1.0 if age_seconds <= 0

        decay = 1.0 - (age_seconds / 86_400.0)
        decay.clamp(0.0, 1.0)
      end

      def keyword_match(tool_name, keywords)
        return 0.0 if keywords.nil? || keywords.empty?

        hits = keywords.count { |kw| tool_name.include?(kw.to_s) }
        hits.to_f / keywords.size
      end
    end
  end
end
