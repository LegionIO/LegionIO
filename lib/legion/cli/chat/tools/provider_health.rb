# frozen_string_literal: true

begin
  require 'legion/cli/chat_command'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class ProviderHealth < Legion::Tools::Base
          tool_name 'legion.provider_health'
          description 'Check the health status of configured LLM providers. Shows circuit breaker state, ' \
                      'routing adjustments, and overall availability. Use this when the user asks about ' \
                      'provider status, LLM health, or routing problems.'
          input_schema({
                         type:       'object',
                         properties: {
                           provider: { type: 'string', description: 'Specific provider to check (optional)' }
                         },
                         required:   []
                       })

          def self.call(provider: nil)
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

          def self.format_report
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

          def self.format_detail(provider)
            entry = provider_detail(provider)
            return "Router not available: #{entry[:error]}" if entry[:error]
            return "Provider not found: #{provider}" if entry.empty?

            lines = ["Provider: #{entry[:provider]}\n"]
            lines << "  Circuit:    #{entry[:circuit]}"
            lines << "  Healthy:    #{entry[:healthy] ? 'YES' : 'NO'}"
            lines << "  Adjustment: #{entry[:adjustment]}"
            lines.join("\n")
          end

          def self.format_circuit_summary(summary)
            format('  Circuits: %<closed>d closed, %<open>d open, %<half>d half-open (of %<total>d)',
                   closed: summary[:closed], open: summary[:open],
                   half: summary[:half_open], total: summary[:total])
          end

          def self.format_entry(entry)
            icon = entry[:healthy] ? '+' : '!'
            suffix = +''
            suffix << " offerings=#{entry[:offerings]}" if entry.key?(:offerings)
            suffix << " models=#{entry[:models].length}" if entry[:models].respond_to?(:length)
            format('  [%<icon>s] %<name>-15s circuit=%<circuit>s adj=%<adj>d%<suffix>s',
                   icon: icon, name: entry[:provider],
                   circuit: entry[:circuit], adj: entry[:adjustment], suffix: suffix)
          end

          def self.provider_stats_available?
            native_provider_stats_available?
          end

          def self.native_provider_stats_available?
            defined?(Legion::LLM::Inventory) && Legion::LLM::Inventory.respond_to?(:providers)
          end

          def self.provider_health_report
            native_provider_health_report
          end

          def self.native_provider_health_report
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

          def self.provider_circuit_summary(report)
            circuits = report.map { |entry| entry[:circuit].to_s }
            {
              total:     report.size,
              closed:    circuits.count('closed'),
              open:      circuits.count('open'),
              half_open: circuits.count('half_open')
            }
          end

          def self.provider_detail(provider)
            provider_name = provider.to_s
            provider_health_report.find { |entry| entry[:provider] == provider_name } || {}
          end

          def self.offering_value(offering, key)
            return unless offering.respond_to?(:[])

            offering[key] || offering[key.to_s]
          end
        end
      end
    end
  end
end
