# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class ModelComparison < RubyLLM::Tool
          description 'Compare LLM model pricing and capabilities side-by-side'

          param :models,
                type:     :string,
                desc:     'Comma-separated model names to compare (blank = show all known models)',
                required: false

          param :tokens,
                type:     :integer,
                desc:     'Hypothetical token count for cost projection (default: 1000)',
                required: false

          def execute(models: nil, tokens: 1000)
            pricing = load_pricing
            selected = filter_models(pricing, models)
            return 'No matching models found.' if selected.empty?

            format_comparison(selected, tokens.to_i)
          end

          private

          def load_pricing
            base = cost_tracker_pricing
            return base unless base.empty?

            default_pricing
          end

          def cost_tracker_pricing
            return {} unless defined?(Legion::LLM::CostTracker)

            Legion::LLM::CostTracker::DEFAULT_PRICING.transform_values do |v|
              { input: v[:input], output: v[:output] }
            end
          rescue StandardError => e
            Legion::Logging.debug("ModelComparison#cost_tracker_pricing failed: #{e.message}") if defined?(Legion::Logging)
            {}
          end

          def default_pricing
            {
              'claude-sonnet-4-6' => { input: 3.0,  output: 15.0 },
              'claude-haiku-4-5'  => { input: 0.80, output: 4.0  },
              'claude-opus-4-6'   => { input: 15.0, output: 75.0 },
              'gpt-4o'            => { input: 2.50, output: 10.0 },
              'gpt-4o-mini'       => { input: 0.15, output: 0.60 }
            }
          end

          def filter_models(pricing, models_str)
            return pricing if models_str.nil? || models_str.strip.empty?

            names = models_str.split(',').map(&:strip).map(&:downcase)
            pricing.select { |k, _| names.any? { |n| k.downcase.include?(n) } }
          end

          def format_comparison(selected, tokens)
            lines = ["Model Comparison (per 1M tokens pricing):\n"]
            lines << '  Model                        Input/$   Output/$    Est. Cost'
            lines << "  #{'—' * 59}"

            sorted = selected.sort_by { |_, v| v[:input] }
            sorted.each do |name, price|
              est = estimate_cost(price, tokens)
              lines << format('  %<name>-25s %<inp>9.2f %<out>10.2f   $%<est>.6f',
                              name: name, inp: price[:input], out: price[:output], est: est)
            end

            lines << ''
            lines << format('  Estimate based on %<t>d input + %<t>d output tokens.', t: tokens)

            if sorted.size > 1
              cheapest = sorted.first
              priciest = sorted.last
              ratio = priciest[1][:input] / cheapest[1][:input]
              lines << format('  %<exp>s is %<r>.1fx more expensive than %<chp>s (input rate).',
                              exp: priciest[0], r: ratio, chp: cheapest[0])
            end

            lines.join("\n")
          end

          def estimate_cost(price, tokens)
            ((tokens * price[:input] / 1_000_000.0) + (tokens * price[:output] / 1_000_000.0)).round(6)
          end
        end
      end
    end
  end
end
