# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'

module Legion
  module CLI
    class Memory < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :global,   type: :boolean, default: false, aliases: ['-g'],
                              desc: 'Use global memory instead of project memory'

      desc 'list', 'List all memory entries'
      def list
        out = formatter
        require 'legion/cli/chat/memory_store'
        scope = options[:global] ? :global : :project
        entries = Chat::MemoryStore.list(scope: scope)

        if entries.empty?
          out.warn('No memory entries found.')
          return
        end

        if options[:json]
          out.json({ entries: entries, scope: scope.to_s })
        else
          out.header("#{scope.to_s.capitalize} Memory (#{entries.length} entries)")
          entries.each { |e| puts "  - #{e}" }
        end
      end
      default_task :list

      desc 'add TEXT', 'Add a memory entry'
      def add(text)
        out = formatter
        require 'legion/cli/chat/memory_store'
        scope = options[:global] ? :global : :project
        path = Chat::MemoryStore.add(text, scope: scope)
        out.success("Added to #{scope} memory (#{path})")
      end

      desc 'forget PATTERN', 'Remove memory entries matching pattern'
      def forget(pattern)
        out = formatter
        require 'legion/cli/chat/memory_store'
        scope = options[:global] ? :global : :project
        removed = Chat::MemoryStore.forget(pattern, scope: scope)

        if removed.zero?
          out.warn("No entries matching '#{pattern}' found.")
        else
          out.success("Removed #{removed} entry/entries matching '#{pattern}'")
        end
      end

      desc 'search QUERY', 'Search memory entries'
      def search(query)
        out = formatter
        require 'legion/cli/chat/memory_store'
        results = Chat::MemoryStore.search(query)

        if results.empty?
          out.warn("No results for '#{query}'")
          return
        end

        if options[:json]
          out.json({ results: results, query: query })
        else
          results.each do |r|
            source = File.basename(File.dirname(r[:source]))
            puts "  #{source}:#{r[:line]} #{r[:text]}"
          end
        end
      end

      desc 'clear', 'Clear all memory entries'
      option :yes, type: :boolean, default: false, aliases: ['-y'], desc: 'Skip confirmation'
      def clear
        out = formatter
        scope = options[:global] ? :global : :project

        unless options[:yes]
          $stderr.print "Clear all #{scope} memory? [y/n] "
          response = $stdin.gets&.strip&.downcase
          return unless %w[y yes].include?(response)
        end

        require 'legion/cli/chat/memory_store'
        if Chat::MemoryStore.clear(scope: scope)
          out.success("#{scope.to_s.capitalize} memory cleared.")
        else
          out.warn('No memory file to clear.')
        end
      end

      desc 'consolidate', 'Consolidate cross-session learnings into global memory'
      option :force, type: :boolean, default: false, aliases: ['-f'],
                     desc: 'Skip gate checks (time, sessions, lock)'
      def consolidate
        out = formatter
        require 'legion/memory/consolidator'

        out.header('Cross-Session Memory Consolidation')

        unless Legion::Memory::Consolidator.enabled?
          out.warn('Consolidation is disabled. Enable with memory.consolidation.enabled: true')
          return
        end

        unless options[:force]
          gates = Legion::Memory::Consolidator.gate_status
          out.detail({
                       'Time gate'    => gates[:time_gate] ? 'pass' : 'fail',
                       'Session gate' => gates[:session_gate] ? 'pass' : 'fail',
                       'Lock gate'    => gates[:lock_gate] ? 'pass' : 'fail'
                     })
        end

        result = Legion::Memory::Consolidator.run(force: options[:force])

        if options[:json]
          out.json(result)
          return
        end

        if result[:success]
          out.success("Consolidated #{result[:insights_count]} insights from #{result[:transcripts_scanned]} sessions")
        else
          out.warn("Consolidation skipped: #{result[:reason]}")
        end
      end

      desc 'status', 'Show consolidation gate status'
      def status
        out = formatter
        require 'legion/memory/consolidator'

        gates = Legion::Memory::Consolidator.gate_status
        settings = Legion::Memory::Consolidator.consolidation_settings

        if options[:json]
          out.json({ gates: gates, settings: settings, enabled: Legion::Memory::Consolidator.enabled? })
          return
        end

        out.header('Consolidation Status')
        out.detail({
                     'Enabled'      => Legion::Memory::Consolidator.enabled?.to_s,
                     'Time gate'    => gates[:time_gate] ? 'pass' : "fail (< #{settings[:min_hours]}h since last run)",
                     'Session gate' => gates[:session_gate] ? 'pass' : "fail (< #{settings[:min_sessions]} new sessions)",
                     'Lock gate'    => gates[:lock_gate] ? 'pass' : 'fail (consolidation in progress)'
                   })
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end
      end
    end
  end
end
