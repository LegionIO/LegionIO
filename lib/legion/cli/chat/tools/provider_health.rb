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
            return 'LLM provider inventory not available.' unless provider_stats_available?

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
            report = provider_health_report
            return "Router not available: #{report[:error]}" if report.is_a?(Hash) && report[:error]
            return 'No providers configured.' if report.empty?

            summary = provider_circuit_summary(report)
            lines = ["Provider Health Report:\n"]
            lines << format_circuit_summary(summary) if summary.is_a?(Hash) && !summary[:error]
            lines << ''
            report.each { |entry| lines << format_entry(entry) }
            lines.join("\n")
          end

          def format_detail(provider)
            entry = provider_detail(provider)
            return "Router not available: #{entry[:error]}" if entry[:error]
            return "Provider not found: #{provider}" if entry.empty?

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
            suffix = +''
            suffix << " offerings=#{entry[:offerings]}" if entry.key?(:offerings)
            suffix << " models=#{entry[:models].length}" if entry[:models].respond_to?(:length)
            format('  [%<icon>s] %<name>-15s circuit=%<circuit>s adj=%<adj>d%<suffix>s',
                   icon: icon, name: entry[:provider],
                   circuit: entry[:circuit], adj: entry[:adjustment], suffix: suffix)
          end

          def provider_stats_available?
            native_provider_stats_available? || gateway_stats_available?
          end

          def native_provider_stats_available?
            defined?(Legion::LLM::Inventory) && Legion::LLM::Inventory.respond_to?(:providers)
          end

          def provider_health_report
            return native_provider_health_report if native_provider_stats_available?

            stats_module.health_report
          end

          def native_provider_health_report
            groups = Legion::LLM::Inventory.providers
            return [] unless groups.respond_to?(:map)

            groups.map do |provider, offerings|
              provider_offerings = Array(offerings)
              health = provider_offerings.map { |offering| offering_value(offering, :health) }
                                         .find { |entry| entry.is_a?(Hash) } || {}
              circuit = health[:circuit_state] || health['circuit_state'] || 'unknown'
              {
                provider:   provider.to_s,
                circuit:    circuit,
                adjustment: health[:adjustment] || health['adjustment'] || 0,
                healthy:    circuit.to_s != 'open',
                offerings:  provider_offerings.size,
                models:     provider_offerings.map { |offering| offering_value(offering, :model) }.compact.uniq,
                types:      provider_offerings.map { |offering| offering_value(offering, :type) }.compact.uniq,
                instances:  provider_offerings.map do |offering|
                  offering_value(offering, :provider_instance) || offering_value(offering, :instance_id)
                end.compact.uniq
              }
            end
          end

          def provider_circuit_summary(report)
            return stats_module.circuit_summary unless native_provider_stats_available?

            circuits = report.map { |entry| entry[:circuit].to_s }
            {
              total:     report.size,
              closed:    circuits.count('closed'),
              open:      circuits.count('open'),
              half_open: circuits.count('half_open')
            }
          end

          def provider_detail(provider)
            provider_name = provider.to_s
            return stats_module.provider_detail(provider: provider_name.to_sym) unless native_provider_stats_available?

            provider_health_report.find { |entry| entry[:provider] == provider_name } || {}
          end

          def offering_value(offering, key)
            return unless offering.respond_to?(:[])

            offering[key] || offering[key.to_s]
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
