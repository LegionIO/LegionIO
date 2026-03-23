# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class ShadowEvalStatus < RubyLLM::Tool
          description 'Show shadow evaluation results comparing primary vs cheaper models'

          param :action,
                type:     :string,
                desc:     'Action: "summary" (default) or "history" (recent evaluations)',
                required: false

          def execute(action: 'summary')
            return 'Shadow evaluation not available.' unless shadow_available?

            case action.to_s
            when 'history' then format_history
            else format_summary
            end
          end

          private

          def shadow_available?
            defined?(Legion::LLM::ShadowEval)
          end

          def format_summary
            s = Legion::LLM::ShadowEval.summary
            lines = ["Shadow Evaluation Summary:\n"]
            lines << format('  Evaluations:      %<v>d', v: s[:total_evaluations])

            if s[:total_evaluations].zero?
              lines << '  No evaluations recorded yet.'
              lines << ''
              lines << '  Enable via settings: llm.shadow.enabled = true'
              return lines.join("\n")
            end

            lines << format('  Avg Length Ratio:  %<v>.2f', v: s[:avg_length_ratio])
            lines << format('  Avg Cost Savings:  %<v>.1f%%', v: s[:avg_cost_savings] * 100)
            lines << format('  Primary Cost:      $%<v>.6f', v: s[:total_primary_cost])
            lines << format('  Shadow Cost:       $%<v>.6f', v: s[:total_shadow_cost])
            lines << format('  Models Tested:     %<v>s', v: s[:models_evaluated].join(', '))

            if s[:avg_cost_savings].positive?
              lines << ''
              lines << format('  Shadow models saved ~%<v>.1f%% on average.',
                              v: s[:avg_cost_savings] * 100)
            end

            lines.join("\n")
          end

          def format_history
            entries = Legion::LLM::ShadowEval.history
            return 'No shadow evaluation history.' if entries.empty?

            lines = [format("Shadow Evaluation History (last %<n>d):\n", n: entries.size)]

            entries.last(10).reverse_each do |entry|
              lines << format(
                '  %<time>s  %<pm>s vs %<sm>s  ratio=%<r>.2f  savings=%<s>.1f%%',
                time: entry[:evaluated_at]&.strftime('%H:%M:%S') || '??:??:??',
                pm:   truncate(entry[:primary_model].to_s, 20),
                sm:   truncate(entry[:shadow_model].to_s, 15),
                r:    entry[:length_ratio],
                s:    (entry[:cost_savings] || 0) * 100
              )
            end

            lines.join("\n")
          end

          def truncate(str, max)
            str.length > max ? "#{str[0, max - 1]}~" : str
          end
        end
      end
    end
  end
end
