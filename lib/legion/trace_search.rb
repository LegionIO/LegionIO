# frozen_string_literal: true

module Legion
  module TraceSearch
    SCHEMA_TEMPLATE = <<~PROMPT
      You translate natural language queries into JSON filter objects for the metering_records table.
      Current date/time: %<current_time>s

      Columns: id (integer), worker_id (string), event_type (string), extension (string),
      runner_function (string), status (string: success/failure), input_tokens (integer),
      output_tokens (integer), cost_usd (float), wall_clock_ms (integer), recorded_at (datetime)

      Return ONLY a valid JSON object with these possible keys:
      - "where": hash of column => value filters (e.g. {"status": "failure"})
      - "order": column name to sort by (prefix with "-" for descending, e.g. "-cost_usd")
      - "limit": integer limit (default 50)
      - "date_from": ISO date string for recorded_at >= filter
      - "date_to": ISO date string for recorded_at <= filter

      For relative time references, compute ISO dates from the current date/time above:
      - "today" => date_from is today's date at 00:00
      - "last hour" => date_from is 1 hour ago
      - "this week" => date_from is Monday of this week
      - "yesterday" => date_from/date_to bracket yesterday

      Examples:
      - "failed tasks" => {"where": {"status": "failure"}}
      - "most expensive calls" => {"order": "-cost_usd", "limit": 20}
      - "tasks by worker-1 today" => {"where": {"worker_id": "worker-1"}, "date_from": "%<today>s"}

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
      input_tokens output_tokens cost_usd wall_clock_ms recorded_at
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
            { role: 'system', content: schema_context },
            { role: 'user',   content: query }
          ],
          schema:   FILTER_SCHEMA
        )
        Legion::Logging.error "[TraceSearch] LLM filter generation failed for query: #{query.inspect}" if !result[:valid] && defined?(Legion::Logging)
        result[:data] if result[:valid]
      end

      def schema_context
        now = Time.now
        format(SCHEMA_TEMPLATE, current_time: now.iso8601, today: now.strftime('%Y-%m-%d'))
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
          dataset = dataset.where { recorded_at >= from } if from
        end
        if parsed[:date_to]
          to = safe_parse_time(parsed[:date_to])
          dataset = dataset.where { recorded_at <= to } if to
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
          Sequel.function(:sum, :input_tokens).as(:total_tokens_in),
          Sequel.function(:sum, :output_tokens).as(:total_tokens_out),
          Sequel.function(:sum, :cost_usd).as(:total_cost),
          Sequel.function(:avg, :wall_clock_ms).as(:avg_latency_ms),
          Sequel.function(:max, :wall_clock_ms).as(:max_latency_ms),
          Sequel.function(:min, :recorded_at).as(:earliest),
          Sequel.function(:max, :recorded_at).as(:latest)
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

      def detect_anomalies(threshold: 2.0)
        return { error: 'data unavailable' } unless data_available?

        now = Time.now.utc
        recent = period_stats(now - 3600, now)
        baseline = period_stats(now - 86_400, now - 3600)

        build_anomaly_report(recent, baseline, threshold)
      rescue StandardError => e
        Legion::Logging.error("[TraceSearch] detect_anomalies failed: #{e.message}") if defined?(Legion::Logging)
        { error: e.message }
      end

      def trend(hours: 24, buckets: 12)
        return { error: 'data unavailable' } unless data_available?

        now = Time.now.utc
        bucket_seconds = (hours * 3600.0 / buckets).to_i
        start_time = now - (hours * 3600)

        data = buckets.times.map do |i|
          bucket_start = start_time + (i * bucket_seconds)
          bucket_end = bucket_start + bucket_seconds
          stats = period_stats(bucket_start, bucket_end)
          { time: bucket_start.iso8601, **stats }
        end

        { buckets: data, hours: hours, bucket_count: buckets, bucket_minutes: bucket_seconds / 60 }
      rescue StandardError => e
        Legion::Logging.error("[TraceSearch] trend failed: #{e.message}") if defined?(Legion::Logging)
        { error: e.message }
      end

      private

      def data_available?
        defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
      end

      def period_stats(from, to)
        ds = Legion::Data.connection[:metering_records].where { recorded_at >= from }.where { recorded_at <= to }
        row = ds.select(
          Sequel.function(:count, Sequel.lit('*')).as(:count),
          Sequel.function(:avg, :cost_usd).as(:avg_cost),
          Sequel.function(:avg, :wall_clock_ms).as(:avg_latency),
          Sequel.function(:sum, :input_tokens).as(:input_tokens),
          Sequel.function(:sum, :output_tokens).as(:output_tokens)
        ).first || {}

        failures = ds.where(status: 'failure').count
        total = row[:count] || 0

        row.merge(failure_rate: total.positive? ? failures.to_f / total : 0.0)
      end

      def build_anomaly_report(recent, baseline, threshold)
        anomalies = []
        anomalies.concat(check_metric(:avg_cost, recent, baseline, threshold, 'Average cost'))
        anomalies.concat(check_metric(:avg_latency, recent, baseline, threshold, 'Average latency'))
        anomalies.concat(check_metric(:failure_rate, recent, baseline, threshold, 'Failure rate'))

        {
          anomalies:       anomalies,
          recent_count:    recent[:count] || 0,
          baseline_count:  baseline[:count] || 0,
          recent_period:   'last 1 hour',
          baseline_period: 'previous 23 hours'
        }
      end

      def check_metric(key, recent, baseline, threshold, label)
        recent_val = (recent[key] || 0).to_f
        baseline_val = (baseline[key] || 0).to_f
        return [] if baseline_val.zero? || recent_val <= baseline_val

        ratio = recent_val / baseline_val
        return [] unless ratio >= threshold

        [{ metric: label, recent: recent_val.round(4), baseline: baseline_val.round(4),
           ratio: ratio.round(2), severity: ratio >= threshold * 2 ? 'critical' : 'warning' }]
      end
    end
  end
end
