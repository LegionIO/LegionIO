# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class SchedulingStatus < RubyLLM::Tool
          description 'Show LLM scheduling and batch queue status: peak/off-peak state, ' \
                      'batch queue depth, and scheduling configuration'

          param :action,
                type:     :string,
                desc:     'Action: "overview" (default), "scheduling" (peak/off-peak detail), "batch" (queue detail)',
                required: false

          def execute(action: 'overview')
            case action.to_s
            when 'scheduling' then format_scheduling
            when 'batch'      then format_batch
            else format_overview
            end
          end

          private

          def format_overview
            lines = ["LLM Scheduling & Batch Overview:\n"]

            if scheduling_available?
              s = Legion::LLM::Scheduling.status
              lines << format('  Scheduling: %<v>s', v: s[:enabled] ? 'enabled' : 'disabled')
              lines << format('  Peak Hours: %<v>s (%<r>s UTC)',
                              v: s[:peak_hours] ? 'YES (peak now)' : 'no (off-peak)',
                              r: s[:peak_range])
            else
              lines << '  Scheduling: not available'
            end

            lines << ''

            if batch_available?
              b = Legion::LLM::Batch.status
              lines << format('  Batch Queue: %<v>s', v: b[:enabled] ? 'enabled' : 'disabled')
              lines << format('  Queue Depth: %<v>d', v: b[:queue_size])
            else
              lines << '  Batch Queue: not available'
            end

            lines.join("\n")
          end

          def format_scheduling
            return 'Scheduling module not available.' unless scheduling_available?

            s = Legion::LLM::Scheduling.status
            lines = ["LLM Scheduling Detail:\n"]
            lines << format('  Enabled:          %<v>s', v: s[:enabled])
            lines << format('  Peak Hours Now:   %<v>s', v: s[:peak_hours])
            lines << format('  Peak Range (UTC): %<v>s', v: s[:peak_range])
            lines << format('  Next Off-Peak:    %<v>s', v: s[:next_off_peak])
            lines << format('  Max Defer Hours:  %<v>d', v: s[:max_defer_hours])
            lines << format('  Defer Intents:    %<v>s', v: Array(s[:defer_intents]).join(', '))
            lines.join("\n")
          end

          def format_batch
            return 'Batch module not available.' unless batch_available?

            b = Legion::LLM::Batch.status
            lines = ["LLM Batch Queue Detail:\n"]
            lines << format('  Enabled:        %<v>s', v: b[:enabled])
            lines << format('  Queue Size:     %<v>d', v: b[:queue_size])
            lines << format('  Max Batch Size: %<v>d', v: b[:max_batch_size])
            lines << format('  Window (sec):   %<v>d', v: b[:window_seconds])

            lines << format('  Oldest Queued:  %<v>s', v: b[:oldest_queued]) if b[:oldest_queued]

            unless (b[:by_priority] || {}).empty?
              lines << ''
              lines << '  By Priority:'
              b[:by_priority].each do |priority, count|
                lines << format('    %<p>-10s %<c>d', p: priority, c: count)
              end
            end

            lines.join("\n")
          end

          def scheduling_available?
            defined?(Legion::LLM::Scheduling)
          end

          def batch_available?
            defined?(Legion::LLM::Batch)
          end
        end
      end
    end
  end
end
