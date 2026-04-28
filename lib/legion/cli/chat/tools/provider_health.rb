# frozen_string_literal: true

require 'ruby_llm'

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class ProviderHealth < RubyLLM::Tool
          description 'Check the health status of configured LLM providers. Shows circuit breaker state, ' \
                      'routing adjustments, and overall availability. Use this when the user asks about ' \
                      'provider status, LLM health, or routing problems.'
          param :provider, type: 'string', desc: 'Specific provider to check (optional)', required: false

          def execute(provider: nil)
            return 'LLM gateway not available.' unless gateway_stats_available?

            if provider
              format_detail(provider.strip)
            else
              format_report
            end
          rescue StandardError => e
            Legion::Logging.warn("ProviderHealth#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error checking provider health: #{e.message}"
          end

          private

          def format_report
            report = stats_module.health_report
            return "Router not available: #{report[:error]}" if report.is_a?(Hash) && report[:error]
            return 'No providers configured.' if report.empty?

            summary = stats_module.circuit_summary
            lines = ["Provider Health Report:\n"]
            lines << format_circuit_summary(summary) if summary.is_a?(Hash) && !summary[:error]
            lines << ''
            report.each { |entry| lines << format_entry(entry) }
            lines.join("\n")
          end

          def format_detail(provider)
            entry = stats_module.provider_detail(provider: provider.to_sym)
            return "Router not available: #{entry[:error]}" if entry[:error]

            lines = ["Provider: #{entry[:provider]}\n"]
            lines << "  Circuit:    #{entry[:circuit]}"
            lines << "  Healthy:    #{entry[:healthy] ? 'YES' : 'NO'}"
            lines << "  Adjustment: #{entry[:adjustment]}"
            lines.join("\n")
          end

          def format_circuit_summary(summary)
            format('  Circuits: %<closed>d closed, %<open>d open, %<half>d half-open (of %<total>d)',
                   closed: summary[:closed], open: summary[:open],
                   half: summary[:half_open], total: summary[:total])
          end

          def format_entry(entry)
            icon = entry[:healthy] ? '+' : '!'
            format('  [%<icon>s] %<name>-15s circuit=%<circuit>s adj=%<adj>d',
                   icon: icon, name: entry[:provider],
                   circuit: entry[:circuit], adj: entry[:adjustment])
          end

          def gateway_stats_available?
            defined?(Legion::Extensions::Llm::Gateway::Runners::ProviderStats)
          end

          def stats_module
            Legion::Extensions::Llm::Gateway::Runners::ProviderStats
          end
        end
      end
    end
  end
end
