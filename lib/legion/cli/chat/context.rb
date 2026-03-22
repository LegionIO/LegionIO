# frozen_string_literal: true

require 'legion/cli/chat_command'
require 'shellwords'

module Legion
  module CLI
    class Chat
      module Context
        PROJECT_MARKERS = {
          'Gemfile'          => :ruby,
          'package.json'     => :javascript,
          'Cargo.toml'       => :rust,
          'go.mod'           => :go,
          'pyproject.toml'   => :python,
          'requirements.txt' => :python,
          'pom.xml'          => :java,
          'build.gradle'     => :java,
          'main.tf'          => :terraform,
          'Makefile'         => :make
        }.freeze

        def self.detect(directory)
          dir = File.expand_path(directory)
          {
            directory:    dir,
            project_type: detect_project_type(dir),
            git_branch:   detect_git_branch(dir),
            git_dirty:    detect_git_dirty(dir),
            project_file: detect_project_file(dir)
          }
        end

        def self.to_system_prompt(directory, extra_dirs: [])
          ctx = detect(directory)
          parts = []
          parts << 'You are Legion, an AI assistant powered by the LegionIO framework.'
          parts << 'You have access to tools for reading files, writing files, editing files, searching, and running shell commands.'
          parts << 'Be concise and helpful. Use markdown formatting for code.'
          parts << ''
          parts << "Working directory: #{ctx[:directory]}"
          parts << "Project type: #{ctx[:project_type]}" if ctx[:project_type]
          parts << "Git branch: #{ctx[:git_branch]}" if ctx[:git_branch]
          parts << 'Uncommitted changes present' if ctx[:git_dirty]

          begin
            require 'legion/cli/chat/extension_tool_loader'
            ext_tools = Chat::ExtensionToolLoader.discover
            if ext_tools.any?
              ext_names = ext_tools.filter_map do |t|
                next unless t.name

                t.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
              end
              parts << "Extension tools available: #{ext_names.join(', ')}"
            end
          rescue LoadError => e
            Legion::Logging.debug("Context#to_system_prompt ExtensionToolLoader not available: #{e.message}") if defined?(Legion::Logging)
          end

          extra_dirs.each do |dir|
            expanded = File.expand_path(dir)
            next unless Dir.exist?(expanded)

            parts << "Additional directory: #{expanded}"
          end

          %w[LEGION.md CLAUDE.md].each do |name|
            path = File.join(ctx[:directory], name)
            next unless File.exist?(path)

            content = File.read(path, encoding: 'utf-8')
            parts << ''
            parts << "# Project Instructions (#{name})"
            parts << content
            break
          end

          parts.join("\n")
        end

        def self.detect_project_type(dir)
          PROJECT_MARKERS.each do |file, type|
            return type if File.exist?(File.join(dir, file))
          end
          nil
        end

        def self.detect_git_branch(dir)
          head = File.join(dir, '.git', 'HEAD')
          return nil unless File.exist?(head)

          ref = File.read(head).strip
          ref.start_with?('ref: refs/heads/') ? ref.sub('ref: refs/heads/', '') : ref[0..7]
        end

        def self.detect_git_dirty(dir)
          return false unless File.exist?(File.join(dir, '.git'))

          output = `cd #{Shellwords.escape(dir)} && git status --porcelain 2>/dev/null`
          !output.strip.empty?
        rescue StandardError => e
          Legion::Logging.debug("Context#detect_git_dirty failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def self.detect_project_file(dir)
          PROJECT_MARKERS.each_key do |file|
            path = File.join(dir, file)
            return path if File.exist?(path)
          end
          nil
        end
      end
    end
  end
end
