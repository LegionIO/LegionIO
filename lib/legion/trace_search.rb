# frozen_string_literal: true

module Legion
  module TraceSearch
    SCHEMA_CONTEXT = <<~PROMPT
      You translate natural language queries into JSON filter objects for the metering_records table.

      Columns: id (integer), worker_id (string), event_type (string), extension (string),
      runner_function (string), status (string: success/failure), tokens_in (integer),
      tokens_out (integer), cost_usd (float), wall_clock_ms (integer), created_at (datetime)

      Return ONLY a valid JSON object with these possible keys:
      - "where": hash of column => value filters (e.g. {"status": "failure"})
      - "order": column name to sort by (prefix with "-" for descending, e.g. "-cost_usd")
      - "limit": integer limit (default 50)
      - "date_from": ISO date string for created_at >= filter
      - "date_to": ISO date string for created_at <= filter

      Examples:
      - "failed tasks" => {"where": {"status": "failure"}}
      - "most expensive calls" => {"order": "-cost_usd", "limit": 20}
      - "tasks by worker-1 today" => {"where": {"worker_id": "worker-1"}, "date_from": "2026-03-16"}

      Return ONLY the JSON object, no explanation.
    PROMPT

    FILTER_SCHEMA = {
      type:       'object',
      properties: {
        where:     { type: 'object' },
        order:     { type: 'string' },
        limit:     { type: 'integer' },
        date_from: { type: 'string' },
        date_to:   { type: 'string' }
      }
    }.freeze

    ALLOWED_COLUMNS = %w[
      id worker_id event_type extension runner_function status
      tokens_in tokens_out cost_usd wall_clock_ms created_at
    ].freeze

    class << self
      def search(query, limit: 50)
        Legion::Logging.info "[TraceSearch] query: #{query.inspect} limit=#{limit}" if defined?(Legion::Logging)
        parsed = generate_filter(query)
        return { results: [], error: 'no filter generated' } unless parsed

        execute_filter(parsed, limit)
      rescue StandardError => e
        Legion::Logging.error "[TraceSearch] search failed: #{e.message}" if defined?(Legion::Logging)
        { results: [], error: e.message }
      end

      def generate_filter(query)
        return nil unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:structured)

        result = Legion::LLM.structured(
          messages: [
            { role: 'system', content: SCHEMA_CONTEXT },
            { role: 'user',   content: query }
          ],
          schema:   FILTER_SCHEMA
        )
        Legion::Logging.error "[TraceSearch] LLM filter generation failed for query: #{query.inspect}" if !result[:valid] && defined?(Legion::Logging)
        result[:data] if result[:valid]
      end

      def execute_filter(parsed, default_limit)
        return { results: [], error: 'data unavailable' } unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection

        ds = Legion::Data.connection[:metering_records]

        if parsed[:where].is_a?(Hash)
          safe_where = parsed[:where].select { |k, _| ALLOWED_COLUMNS.include?(k.to_s) }
          ds = ds.where(safe_where.transform_keys(&:to_sym))
        end

        ds = apply_date_filters(ds, parsed)
        ds = apply_ordering(ds, parsed)

        limit = [parsed[:limit] || default_limit, 200].min
        total = ds.count
        results = ds.limit(limit).all
        { results: results, count: results.size, total: total, truncated: total > limit, filter: parsed }
      end

      def apply_date_filters(dataset, parsed)
        if parsed[:date_from]
          from = safe_parse_time(parsed[:date_from])
          dataset = dataset.where { created_at >= from } if from
        end
        if parsed[:date_to]
          to = safe_parse_time(parsed[:date_to])
          dataset = dataset.where { created_at <= to } if to
        end
        dataset
      end

      def safe_parse_time(value)
        return value if value.is_a?(Time)

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def apply_ordering(dataset, parsed)
        return dataset unless parsed[:order].is_a?(String)

        col = parsed[:order].delete_prefix('-')
        return dataset unless ALLOWED_COLUMNS.include?(col)

        parsed[:order].start_with?('-') ? dataset.order(Sequel.desc(col.to_sym)) : dataset.order(col.to_sym)
      end

      def summarize(query)
        parsed = generate_filter(query)
        return { error: 'no filter generated' } unless parsed

        compute_summary(parsed)
      rescue StandardError => e
        Legion::Logging.error("[TraceSearch] summarize failed: #{e.message}") if defined?(Legion::Logging)
        { error: e.message }
      end

      def compute_summary(parsed)
        return { error: 'data unavailable' } unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection

        ds = build_filtered_dataset(parsed)
        row = aggregate_stats(ds)

        format_summary(ds, row, parsed)
      end

      def build_filtered_dataset(parsed)
        ds = Legion::Data.connection[:metering_records]
        if parsed[:where].is_a?(Hash)
          safe_where = parsed[:where].select { |k, _| ALLOWED_COLUMNS.include?(k.to_s) }
          ds = ds.where(safe_where.transform_keys(&:to_sym))
        end
        apply_date_filters(ds, parsed)
      end

      def aggregate_stats(dataset)
        dataset.select(
          Sequel.function(:count, Sequel.lit('*')).as(:total_records),
          Sequel.function(:sum, :tokens_in).as(:total_tokens_in),
          Sequel.function(:sum, :tokens_out).as(:total_tokens_out),
          Sequel.function(:sum, :cost_usd).as(:total_cost),
          Sequel.function(:avg, :wall_clock_ms).as(:avg_latency_ms),
          Sequel.function(:max, :wall_clock_ms).as(:max_latency_ms),
          Sequel.function(:min, :created_at).as(:earliest),
          Sequel.function(:max, :created_at).as(:latest)
        ).first || {}
      end

      def format_summary(dataset, row, parsed)
        {
          total_records:    row[:total_records] || 0,
          total_tokens_in:  row[:total_tokens_in] || 0,
          total_tokens_out: row[:total_tokens_out] || 0,
          total_cost:       (row[:total_cost] || 0).to_f.round(4),
          avg_latency_ms:   (row[:avg_latency_ms] || 0).to_f.round(1),
          max_latency_ms:   row[:max_latency_ms] || 0,
          time_range:       { from: row[:earliest], to: row[:latest] },
          status_counts:    dataset.group_and_count(:status).all.to_h { |r| [r[:status], r[:count]] },
          top_extensions:   top_by(dataset, :extension).map { |r| { name: r[:extension], count: r[:count] } },
          top_workers:      top_by(dataset, :worker_id).map { |r| { id: r[:worker_id], count: r[:count] } },
          filter:           parsed
        }
      end

      def top_by(dataset, column, limit: 5)
        dataset.group_and_count(column).order(Sequel.desc(:count)).limit(limit).all
      end
    end
  end
end
