# frozen_string_literal: true

require 'fileutils'
require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module MemoryStore
        DEFAULT_PROJECT_FILE = '.legion/memory.md'
        DEFAULT_GLOBAL_DIR   = File.join(Dir.home, '.legion', 'memory')
        DEFAULT_GLOBAL_FILE  = File.join(DEFAULT_GLOBAL_DIR, 'global.md')

        module_function

        def project_path(base_dir = Dir.pwd)
          File.join(base_dir, DEFAULT_PROJECT_FILE)
        end

        def global_path
          DEFAULT_GLOBAL_FILE
        end

        def load_all(base_dir = Dir.pwd)
          memories = []
          [global_path, project_path(base_dir)].each do |path|
            next unless File.exist?(path)

            memories << { source: path, content: File.read(path, encoding: 'utf-8') }
          end
          memories
        end

        def load_context(base_dir = Dir.pwd)
          parts = load_all(base_dir).map do |m|
            label = m[:source].include?('global') ? 'Global Memory' : 'Project Memory'
            "## #{label}\n\n#{m[:content]}"
          end
          return nil if parts.empty?

          parts.join("\n\n---\n\n")
        end

        def add(text, scope: :project, base_dir: Dir.pwd)
          path = scope == :global ? global_path : project_path(base_dir)
          ensure_dir(path)

          timestamp = Time.now.strftime('%Y-%m-%d %H:%M')
          entry = "\n- #{text} _(#{timestamp})_\n"

          if File.exist?(path)
            File.open(path, 'a', encoding: 'utf-8') { |f| f.write(entry) }
          else
            header = scope == :global ? "# Global Memory\n" : "# Project Memory\n"
            File.write(path, "#{header}#{entry}", encoding: 'utf-8')
          end
          path
        end

        def forget(pattern, scope: :project, base_dir: Dir.pwd)
          path = scope == :global ? global_path : project_path(base_dir)
          return 0 unless File.exist?(path)

          lines = File.readlines(path, encoding: 'utf-8')
          original_count = lines.length
          lines.reject! { |line| line.include?(pattern) }
          removed = original_count - lines.length
          File.write(path, lines.join, encoding: 'utf-8')
          removed
        end

        def list(scope: :project, base_dir: Dir.pwd)
          path = scope == :global ? global_path : project_path(base_dir)
          return [] unless File.exist?(path)

          File.readlines(path, encoding: 'utf-8')
              .select { |line| line.start_with?('- ') }
              .map { |line| line.sub(/\A- /, '').strip }
        end

        def clear(scope: :project, base_dir: Dir.pwd)
          path = scope == :global ? global_path : project_path(base_dir)
          return false unless File.exist?(path)

          File.delete(path)
          true
        end

        def search(query, base_dir: Dir.pwd)
          results = []
          load_all(base_dir).each do |m|
            m[:content].lines.each_with_index do |line, idx|
              next unless line.downcase.include?(query.downcase)

              results << { source: m[:source], line: idx + 1, text: line.strip }
            end
          end
          results
        end

        def ensure_dir(path)
          FileUtils.mkdir_p(File.dirname(path))
        end
        private_class_method :ensure_dir
      end
    end
  end
end
