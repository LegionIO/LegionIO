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
        parsed = generate_filter(query)
        return { results: [], error: 'no filter generated' } unless parsed

        execute_filter(parsed, limit)
      rescue StandardError => e
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
        result[:data] if result[:valid]
      end

      def execute_filter(parsed, default_limit)
        return { results: [], error: 'data unavailable' } unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection

        ds = Legion::Data.connection[:metering_records]

        if parsed[:where].is_a?(Hash)
          safe_where = parsed[:where].select { |k, _| ALLOWED_COLUMNS.include?(k.to_s) }
          ds = ds.where(safe_where.transform_keys(&:to_sym))
        end

        ds = ds.where { created_at >= parsed[:date_from] } if parsed[:date_from]
        ds = ds.where { created_at <= parsed[:date_to] } if parsed[:date_to]

        if parsed[:order].is_a?(String)
          col = parsed[:order].delete_prefix('-')
          if ALLOWED_COLUMNS.include?(col)
            ds = parsed[:order].start_with?('-') ? ds.order(Sequel.desc(col.to_sym)) : ds.order(col.to_sym)
          end
        end

        limit = [parsed[:limit] || default_limit, 200].min
        results = ds.limit(limit).all
        { results: results, count: results.size, filter: parsed }
      end
    end
  end
end
