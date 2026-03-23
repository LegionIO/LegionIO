# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class ArbitrageStatus < RubyLLM::Tool
          description 'Show LLM cost arbitrage status: model pricing table, cheapest model per capability tier'

          param :capability,
                type:     :string,
                desc:     'Capability tier to check: basic, moderate, or reasoning (default: show all)',
                required: false

          TIERS = %i[basic moderate reasoning].freeze

          def execute(capability: nil)
            return 'LLM arbitrage module not available.' unless arbitrage_available?

            if capability
              format_tier(capability.to_sym)
            else
              format_overview
            end
          end

          private

          def arbitrage_available?
            defined?(Legion::LLM::Arbitrage)
          end

          def format_overview
            arb = Legion::LLM::Arbitrage
            lines = ["LLM Cost Arbitrage\n"]
            lines << format('  Enabled: %<v>s', v: arb.enabled? ? 'YES' : 'no')
            lines << ''
            lines << '  Cost Table (per 1M tokens):'
            lines << '  Model                                       Input   Output'
            lines << "  #{'—' * 58}"

            arb.cost_table.sort_by { |_, v| v[:input] }.each do |model, costs|
              lines << format('  %<m>-40s %<i>7.2f %<o>8.2f',
                              m: model, i: costs[:input], o: costs[:output])
            end

            if arb.enabled?
              lines << ''
              lines << '  Cheapest per tier:'
              TIERS.each do |tier|
                pick = arb.cheapest_for(capability: tier)
                lines << format('    %<tier>-12s -> %<pick>s', tier: tier, pick: pick || 'none')
              end
            end

            lines.join("\n")
          end

          def format_tier(tier)
            arb = Legion::LLM::Arbitrage
            return format('Invalid tier: %<t>s. Use: %<valid>s', t: tier, valid: TIERS.join(', ')) unless TIERS.include?(tier)

            pick = arb.cheapest_for(capability: tier)
            cost = pick ? arb.estimated_cost(model: pick) : nil

            lines = [format("Arbitrage for tier: %<t>s\n", t: tier)]
            if pick
              lines << format('  Selected model: %<m>s', m: pick)
              lines << format('  Estimated cost: $%<c>.6f (1K in + 500 out)', c: cost) if cost
            else
              lines << '  No eligible model found (arbitrage may be disabled)'
            end
            lines.join("\n")
          end
        end
      end
    end
  end
end
