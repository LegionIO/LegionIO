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
        class BudgetStatus < RubyLLM::Tool
          description 'Check the current LLM session cost budget status. Shows how much has been spent, ' \
                      'remaining budget, and whether the budget guard is enforcing limits. Works locally ' \
                      'without needing the Legion daemon. Use this when the user asks about spending or budget.'
          param :action, type:     'string',
                         desc:     'Action: "status" (default), "summary" (cost breakdown by model)',
                         required: false

          def execute(action: 'status')
            return 'Legion::LLM not available.' unless llm_available?

            case action.to_s
            when 'summary' then format_summary
            else format_status
            end
          rescue StandardError => e
            Legion::Logging.warn("BudgetStatus#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error checking budget: #{e.message}"
          end

          private

          def format_status
            guard = budget_guard_status
            tracker = cost_summary
            lines = ["Session Budget Status:\n"]
            lines << format('  Enforcing:  %<val>s', val: guard[:enforcing] ? 'YES' : 'no')
            lines << format('  Budget:     $%<val>.4f', val: guard[:budget_usd]) if guard[:enforcing]
            lines << format('  Spent:      $%<val>.6f', val: tracker[:total_cost_usd])
            lines << format('  Remaining:  $%<val>.4f', val: guard[:remaining_usd]) if guard[:remaining_usd]
            lines << format('  Usage:      %<val>.1f%%', val: guard[:ratio] * 100) if guard[:enforcing]
            lines << format('  Requests:   %<val>d', val: tracker[:total_requests])
            lines << format('  Tokens In:  %<val>d', val: tracker[:total_input_tokens])
            lines << format('  Tokens Out: %<val>d', val: tracker[:total_output_tokens])
            lines.join("\n")
          end

          def format_summary
            tracker = cost_summary
            return 'No LLM requests recorded this session.' if tracker[:total_requests].zero?

            lines = ["Session Cost Summary:\n"]
            lines << format('  Total:    $%<cost>.6f (%<reqs>d requests)',
                            cost: tracker[:total_cost_usd], reqs: tracker[:total_requests])
            lines << format('  Tokens:   %<inp>d in / %<out>d out',
                            inp: tracker[:total_input_tokens], out: tracker[:total_output_tokens])

            append_model_breakdown(lines, tracker[:by_model])
            lines.join("\n")
          end

          def append_model_breakdown(lines, by_model)
            return unless by_model&.any?

            lines << "\n  By Model:"
            by_model.each do |model, data|
              lines << format('    %<model>-30s $%<cost>.6f (%<reqs>d requests)',
                              model: model, cost: data[:cost_usd], reqs: data[:requests])
            end
          end

          def budget_guard_status
            return { enforcing: false, budget_usd: 0.0, ratio: 0.0 } unless budget_guard_available?

            Legion::LLM::Hooks::BudgetGuard.status
          end

          def cost_summary
            return empty_summary unless cost_tracker_available?

            Legion::LLM::CostTracker.summary
          end

          def budget_guard_available?
            defined?(Legion::LLM::Hooks::BudgetGuard)
          end

          def cost_tracker_available?
            defined?(Legion::LLM::CostTracker)
          end

          def llm_available?
            defined?(Legion::LLM)
          end

          def empty_summary
            { total_cost_usd: 0.0, total_requests: 0, total_input_tokens: 0, total_output_tokens: 0, by_model: {} }
          end
        end
      end
    end
  end
end
