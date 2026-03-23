# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class EscalationStatus < RubyLLM::Tool
          description 'Show model escalation history: how often cheaper models get upgraded to more capable ones'

          param :action,
                type:     :string,
                desc:     'Action: "summary" (default) or "rate" (escalation frequency)',
                required: false

          def execute(action: 'summary')
            return 'Escalation tracker not available.' unless tracker_available?

            case action.to_s
            when 'rate' then format_rate
            else format_summary
            end
          end

          private

          def tracker_available?
            defined?(Legion::LLM::EscalationTracker)
          end

          def format_summary
            s = Legion::LLM::EscalationTracker.summary
            lines = ["Model Escalation Summary:\n"]
            lines << format('  Total Escalations: %<v>d', v: s[:total_escalations])

            if s[:total_escalations].zero?
              lines << '  No escalations recorded.'
              return lines.join("\n")
            end

            unless s[:by_reason].empty?
              lines << ''
              lines << '  By Reason:'
              s[:by_reason].sort_by { |_, c| -c }.each do |reason, count|
                lines << format('    %<r>-20s %<c>d', r: reason, c: count)
              end
            end

            unless s[:by_target_model].empty?
              lines << ''
              lines << '  Escalated To:'
              s[:by_target_model].sort_by { |_, c| -c }.each do |model, count|
                lines << format('    %<m>-25s %<c>d', m: model, c: count)
              end
            end

            unless s[:recent].empty?
              lines << ''
              lines << '  Recent:'
              s[:recent].first(5).each do |entry|
                lines << format('    %<from>s -> %<to>s (%<reason>s)',
                                from: entry[:from_model], to: entry[:to_model], reason: entry[:reason])
              end
            end

            lines.join("\n")
          end

          def format_rate
            rate = Legion::LLM::EscalationTracker.escalation_rate
            format('Escalation Rate: %<c>d escalations in the last %<m>d minutes',
                   c: rate[:count], m: rate[:window_seconds] / 60)
          end
        end
      end
    end
  end
end
