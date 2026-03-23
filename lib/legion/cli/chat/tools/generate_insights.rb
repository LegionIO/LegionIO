# frozen_string_literal: true

require 'ruby_llm'
require 'net/http'
require 'json'

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class GenerateInsights < RubyLLM::Tool
          description 'Generate a comprehensive system insights report by combining anomaly detection, trend analysis, ' \
                      'worker health, and knowledge stats into a single actionable summary. Use this for periodic ' \
                      'health reviews or when you want a high-level overview of system behavior.'

          DEFAULT_PORT = 4567
          DEFAULT_HOST = '127.0.0.1'

          def execute
            sections = gather_sections
            return 'Legion daemon not running (cannot reach API).' if sections.values.all?(&:nil?)

            format_insights(sections)
          rescue Errno::ECONNREFUSED
            'Legion daemon not running (cannot reach API).'
          rescue StandardError => e
            Legion::Logging.warn("GenerateInsights#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error generating insights: #{e.message}"
          end

          private

          def gather_sections
            {
              health:     safe_fetch('/api/health'),
              anomalies:  safe_fetch('/api/traces/anomalies'),
              trend:      safe_fetch('/api/traces/trend?hours=24&buckets=6'),
              apollo:     safe_fetch('/api/apollo/stats'),
              graph:      safe_fetch('/api/apollo/graph'),
              workers:    safe_fetch('/api/workers'),
              scheduling: scheduling_status,
              llm:        llm_status
            }
          end

          def safe_fetch(path)
            api_get(path)
          rescue StandardError
            nil
          end

          def format_insights(sections)
            lines = ["System Insights Report\n"]
            lines << format_health(sections[:health])
            lines << format_anomaly_section(sections[:anomalies])
            lines << format_trend_section(sections[:trend])
            lines << format_apollo_section(sections[:apollo])
            lines << format_graph_section(sections[:graph])
            lines << format_worker_section(sections[:workers])
            lines << format_scheduling_section(sections[:scheduling])
            lines << format_llm_section(sections[:llm])
            lines << recommendations(sections)
            lines.compact.join("\n\n")
          end

          def format_health(data)
            return nil unless data

            d = data[:data] || data
            "Health: #{d[:status] || 'unknown'} | Version: #{d[:version] || '?'}"
          end

          def format_anomaly_section(data)
            return nil unless data

            d = data[:data] || data
            anomalies = d[:anomalies] || []
            if anomalies.empty?
              'Anomalies: None detected (system nominal)'
            else
              items = anomalies.map { |a| "  - [#{(a[:severity] || 'warning').upcase}] #{a[:metric]} (#{a[:ratio]}x)" }
              "Anomalies (#{anomalies.size}):\n#{items.join("\n")}"
            end
          end

          def format_trend_section(data)
            return nil unless data

            d = data[:data] || data
            buckets = d[:buckets] || []
            return nil if buckets.empty?

            first = buckets.first
            last = buckets.last
            vol_change = percent_change(first[:count], last[:count])
            cost_change = percent_change(first[:avg_cost], last[:avg_cost])

            "Trend (24h): Volume #{vol_change} | Cost #{cost_change}"
          end

          def format_apollo_section(data)
            return nil unless data

            d = data[:data] || data
            return nil if d[:error]

            "Knowledge: #{d[:total_entries] || 0} entries | 24h: #{d[:recent_24h] || 0} | " \
              "Confidence: #{d[:avg_confidence] || 0}"
          end

          def format_worker_section(data)
            return nil unless data

            workers = data[:data] || []
            workers = Array(workers)
            return nil if workers.empty?

            active = workers.count { |w| w[:lifecycle_state] == 'active' }
            "Workers: #{active}/#{workers.size} active"
          end

          def format_graph_section(data)
            return nil unless data

            d = data[:data] || data
            return nil if d[:error]

            disputed = d[:disputed_entries] || 0
            domains = (d[:domains] || {}).size
            relations = d[:total_relations] || 0

            "Graph: #{domains} domains | #{relations} relations | #{disputed} disputed"
          end

          def format_scheduling_section(data)
            return nil unless data

            peak = data[:peak_hours] ? 'PEAK' : 'off-peak'
            batch_size = data.dig(:batch, :queue_size) || 0

            "Scheduling: #{peak} | Batch queue: #{batch_size}"
          end

          def format_llm_section(data)
            return nil unless data

            parts = []
            parts << "Escalations: #{data[:escalations]}" if data[:escalations]
            parts << "Shadow evals: #{data[:shadow_evals]}" if data[:shadow_evals]
            return nil if parts.empty?

            "LLM: #{parts.join(' | ')}"
          end

          def scheduling_status
            result = {}
            if defined?(Legion::LLM::Scheduling)
              s = Legion::LLM::Scheduling.status
              result.merge!(s)
            end
            result[:batch] = Legion::LLM::Batch.status if defined?(Legion::LLM::Batch)
            result.empty? ? nil : result
          rescue StandardError
            nil
          end

          def llm_status
            result = {}
            if defined?(Legion::LLM::EscalationTracker)
              s = Legion::LLM::EscalationTracker.summary
              result[:escalations] = s[:total_escalations]
            end
            if defined?(Legion::LLM::ShadowEval)
              s = Legion::LLM::ShadowEval.summary
              result[:shadow_evals] = s[:total_evaluations]
            end
            result.empty? ? nil : result
          rescue StandardError
            nil
          end

          def recommendations(sections)
            recs = []
            add_anomaly_recs(recs, sections[:anomalies])
            add_trend_recs(recs, sections[:trend])
            return nil if recs.empty?

            "Recommendations:\n#{recs.map { |r| "  * #{r}" }.join("\n")}"
          end

          def add_anomaly_recs(recs, data)
            return unless data

            anomalies = (data[:data] || data)[:anomalies] || []
            anomalies.each do |a|
              case a[:metric]
              when /cost/i
                recs << 'Review recent high-cost operations — consider model downgrade for non-critical tasks'
              when /latency/i
                recs << 'Investigate latency spike — check provider health or fleet worker load'
              when /failure/i
                recs << 'Elevated failure rate — check extension health and transport connectivity'
              end
            end
          end

          def add_trend_recs(recs, data)
            return unless data

            buckets = (data[:data] || data)[:buckets] || []
            return if buckets.size < 2

            last = buckets.last
            recs << 'Failure rate above 10% in most recent period — investigate immediately' if last[:failure_rate].to_f > 0.1
            return unless last[:count].to_i.zero? && buckets.size > 2

            recs << 'No recent activity detected — verify daemon extensions are running'
          end

          def percent_change(first_val, last_val)
            f = (first_val || 0).to_f
            l = (last_val || 0).to_f
            return 'stable' if f.zero? && l.zero?
            return 'rising' if f.zero?

            pct = ((l - f) / f * 100).round(0)
            if pct > 10
              "rising (+#{pct}%)"
            elsif pct < -10
              "falling (#{pct}%)"
            else
              "stable (#{pct}%)"
            end
          end

          def api_get(path)
            uri = URI("http://#{DEFAULT_HOST}:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            response = http.get(uri.request_uri)
            ::JSON.parse(response.body, symbolize_names: true)
          end

          def api_port
            return DEFAULT_PORT unless defined?(Legion::Settings)

            Legion::Settings[:api]&.dig(:port) || DEFAULT_PORT
          rescue StandardError
            DEFAULT_PORT
          end
        end
      end
    end
  end
end
