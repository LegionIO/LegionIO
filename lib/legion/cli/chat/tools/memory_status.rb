# frozen_string_literal: true

module Legion
  module CLI
    class Chat
      module Tools
        class MemoryStatus < RubyLLM::Tool
          description 'Show persistent memory status: project and global memory entries, ' \
                      'Apollo knowledge store stats, and session history overview'

          param :action,
                type:     :string,
                desc:     'Action: "overview" (default), "memories" (local memory detail), ' \
                          '"apollo" (knowledge graph stats), "sessions" (saved session list)',
                required: false

          def execute(action: 'overview')
            case action.to_s
            when 'memories' then format_memories
            when 'apollo'   then format_apollo
            when 'sessions' then format_sessions
            else format_overview
            end
          end

          private

          def format_overview
            lines = ["Memory & Knowledge Overview:\n"]

            mem = memory_stats
            lines << format('  Local Memory:   %<p>d project, %<g>d global entries', p: mem[:project], g: mem[:global])

            apollo = apollo_stats
            lines << if apollo
                       format('  Apollo Store:   %<t>d entries (%<c>d confirmed, %<d>d disputed)',
                              t: apollo[:total] || 0, c: apollo[:confirmed] || 0, d: apollo[:disputed] || 0)
                     else
                       '  Apollo Store:   not available'
                     end

            sessions = session_list
            lines << format('  Saved Sessions: %<c>d', c: sessions.size)

            lines.join("\n")
          end

          def format_memories
            require 'legion/cli/chat/memory_store'
            lines = ["Persistent Memory Detail:\n"]

            project = Chat::MemoryStore.list(scope: :project)
            lines << '  Project Memory:'
            if project.empty?
              lines << '    (no entries)'
            else
              project.each_with_index do |entry, i|
                lines << format('    %<i>d. %<e>s', i: i + 1, e: truncate(entry, 100))
              end
            end

            lines << ''
            global = Chat::MemoryStore.list(scope: :global)
            lines << '  Global Memory:'
            if global.empty?
              lines << '    (no entries)'
            else
              global.each_with_index do |entry, i|
                lines << format('    %<i>d. %<e>s', i: i + 1, e: truncate(entry, 100))
              end
            end

            lines.join("\n")
          end

          def format_apollo
            stats = apollo_stats
            return 'Apollo knowledge store is not available.' unless stats

            lines = ["Apollo Knowledge Store:\n"]
            lines << format('  Total Entries:  %<v>d', v: stats[:total] || 0)
            lines << format('  Confirmed:      %<v>d', v: stats[:confirmed] || 0)
            lines << format('  Candidates:     %<v>d', v: stats[:candidates] || 0)
            lines << format('  Disputed:       %<v>d', v: stats[:disputed] || 0)
            lines << format('  Recent (24h):   %<v>d', v: stats[:recent_24h] || 0)
            lines << format('  Avg Confidence: %<v>.2f', v: stats[:avg_confidence] || 0.0)

            if stats[:domains]
              lines << ''
              lines << '  Domains:'
              stats[:domains].each do |domain, count|
                lines << format('    %<d>-20s %<c>d entries', d: domain, c: count)
              end
            end

            lines.join("\n")
          end

          def format_sessions
            require 'legion/cli/chat/session_store'
            sessions = Chat::SessionStore.list
            return 'No saved sessions found.' if sessions.empty?

            lines = [format("Saved Sessions (%<c>d):\n", c: sessions.size)]
            sessions.first(10).each do |s|
              age = time_ago(s[:modified])
              lines << format('  %<n>-20s %<m>3d msgs  %<a>s  %<s>s',
                              n: s[:name], m: s[:message_count] || 0, a: age, s: s[:model] || '')
              lines << format('    %<v>s', v: truncate(s[:summary].to_s, 80)) if s[:summary]
            end
            lines << format('  ... and %<n>d more', n: sessions.size - 10) if sessions.size > 10

            lines.join("\n")
          end

          def memory_stats
            require 'legion/cli/chat/memory_store'
            {
              project: Chat::MemoryStore.list(scope: :project).size,
              global:  Chat::MemoryStore.list(scope: :global).size
            }
          rescue StandardError
            { project: 0, global: 0 }
          end

          def apollo_stats
            return nil unless apollo_available?

            data = safe_fetch('/api/apollo/stats')
            return nil unless data

            data[:data] || data
          rescue StandardError
            nil
          end

          def session_list
            require 'legion/cli/chat/session_store'
            Chat::SessionStore.list
          rescue StandardError
            []
          end

          def apollo_available?
            defined?(Legion::Data)
          end

          def safe_fetch(path)
            require 'net/http'
            uri = URI("http://127.0.0.1:#{api_port}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 2
            http.read_timeout = 5
            response = http.request(Net::HTTP::Get.new(uri))
            return nil unless response.is_a?(Net::HTTPSuccess)

            Legion::JSON.load(response.body)
          rescue StandardError
            nil
          end

          def api_port
            (defined?(Legion::Settings) && Legion::Settings[:api] && Legion::Settings[:api][:port]) || 4567
          end

          def truncate(str, max)
            str.length > max ? "#{str[0, max]}..." : str
          end

          def time_ago(time)
            return '?' unless time

            seconds = Time.now - time
            if seconds < 3600
              format('%<m>dm ago', m: (seconds / 60).to_i)
            elsif seconds < 86_400
              format('%<h>dh ago', h: (seconds / 3600).to_i)
            else
              format('%<d>dd ago', d: (seconds / 86_400).to_i)
            end
          end
        end
      end
    end
  end
end
