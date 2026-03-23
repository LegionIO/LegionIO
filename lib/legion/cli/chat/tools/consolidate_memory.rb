# frozen_string_literal: true

require 'ruby_llm'

begin
  require 'legion/cli/chat_command'
  require 'legion/cli/chat/memory_store'
rescue LoadError
  nil
end

module Legion
  module CLI
    class Chat
      module Tools
        class ConsolidateMemory < RubyLLM::Tool
          description 'Consolidate and organize memory entries by removing duplicates, merging related items, ' \
                      'and creating cleaner summaries. Use this when memory has grown cluttered or has redundant entries. ' \
                      'Pass scope "project" or "global" to target the right memory file.'
          param :scope, type: 'string', desc: 'Memory scope: "project" or "global" (default: project)'
          param :dry_run, type: 'string', desc: 'Set to "true" to preview without writing (default: false)', required: false

          CONSOLIDATION_PROMPT = <<~PROMPT
            You are a memory consolidation engine. Given a list of memory entries, produce a cleaned-up version that:

            1. Removes exact or near-duplicate entries (keep the most complete version)
            2. Merges entries about the same topic into a single clear statement
            3. Preserves all unique and valuable information
            4. Keeps entries concise — one line per memory
            5. Drops entries that are purely temporary or session-specific
            6. Preserves the most recent timestamp when merging

            Return ONLY the consolidated entries, one per line, each prefixed with "- ".
            Do NOT add headers, explanations, or commentary.
          PROMPT

          def execute(scope: 'project', dry_run: nil)
            dry_run = dry_run.to_s == 'true'
            scope_sym = scope.to_s == 'global' ? :global : :project

            entries = MemoryStore.list(scope: scope_sym)
            return "No memory entries found in #{scope} scope." if entries.empty?
            return "Only #{entries.size} entries — no consolidation needed." if entries.size < 3

            consolidated = consolidate_entries(entries)
            return 'Consolidation failed: could not generate summary.' unless consolidated

            new_entries = parse_consolidated(consolidated)
            removed = entries.size - new_entries.size

            if dry_run
              preview = new_entries.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n")
              "Preview (#{entries.size} -> #{new_entries.size}, #{removed} removed):\n\n#{preview}"
            else
              write_consolidated(new_entries, scope_sym)
              "Consolidated #{scope} memory: #{entries.size} -> #{new_entries.size} entries (#{removed} removed/merged)"
            end
          rescue StandardError => e
            Legion::Logging.warn("ConsolidateMemory#execute failed: #{e.message}") if defined?(Legion::Logging)
            "Error consolidating memory: #{e.message}"
          end

          private

          def consolidate_entries(entries)
            return nil unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat_direct)

            numbered = entries.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n")

            session = Legion::LLM.chat_direct(model: nil, provider: nil)
            response = session.ask("#{CONSOLIDATION_PROMPT}\n\nCurrent entries:\n#{numbered}")
            response.content
          end

          def parse_consolidated(text)
            text.lines
                .map(&:strip)
                .select { |line| line.start_with?('- ') }
                .map { |line| line.sub(/\A- /, '').strip }
                .reject(&:empty?)
          end

          def write_consolidated(entries, scope_sym)
            path = scope_sym == :global ? MemoryStore.global_path : MemoryStore.project_path
            header = scope_sym == :global ? "# Global Memory\n" : "# Project Memory\n"
            timestamp = Time.now.strftime('%Y-%m-%d %H:%M')

            content = header
            content += "\n_Consolidated on #{timestamp}_\n"
            entries.each { |entry| content += "\n- #{entry}\n" }

            MemoryStore.send(:ensure_dir, path)
            File.write(path, content, encoding: 'utf-8')
          end
        end
      end
    end
  end
end
