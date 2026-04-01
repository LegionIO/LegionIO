# frozen_string_literal: true

require 'yaml'

module Legion
  module Chat
    module Skills
      SKILL_DIRS = ['.legion/skills', '~/.legionio/skills'].freeze

      class << self
        def discover
          SKILL_DIRS.flat_map do |dir|
            expanded = File.expand_path(dir)
            next [] unless Dir.exist?(expanded)

            md_skills = Dir.glob(File.join(expanded, '*.md')).filter_map { |f| parse(f) }
            rb_skills = Dir.glob(File.join(expanded, '*.rb')).filter_map { |f| parse_rb(f) }
            md_skills + rb_skills
          end
        end

        def find(name)
          discover.find { |s| s[:name] == name.to_s }
        end

        def parse(path)
          content = File.read(path)
          return nil unless content.start_with?('---')

          parts = content.split(/^---\s*$/, 3)
          return nil if parts.size < 3

          frontmatter = YAML.safe_load(parts[1], permitted_classes: [Symbol])
          body = parts[2]&.strip

          {
            name:        frontmatter['name'] || File.basename(path, '.md'),
            description: frontmatter['description'] || '',
            type:        :prompt,
            model:       frontmatter['model'],
            tools:       Array(frontmatter['tools']),
            prompt:      body,
            path:        path
          }
        rescue StandardError => e
          Legion::Logging.warn "Skill parse error #{path}: #{e.message}" if defined?(Legion::Logging)
          nil
        end

        def parse_rb(path)
          content = File.read(path)

          name = File.basename(path, '.rb')
          description = content.match(/^\s*#\s*description:\s*(.+)$/i)&.captures&.first || ''
          model = content.match(/^\s*#\s*model:\s*(.+)$/i)&.captures&.first

          {
            name:        name,
            description: description.strip,
            type:        :ruby,
            model:       model&.strip,
            tools:       [],
            prompt:      nil,
            path:        path
          }
        rescue StandardError => e
          Legion::Logging.warn "Skill parse_rb error #{path}: #{e.message}" if defined?(Legion::Logging)
          nil
        end

        def execute(skill, input: nil)
          case skill[:type]
          when :ruby
            execute_rb(skill, input: input)
          when :prompt
            execute_prompt(skill, input: input)
          else
            { success: false, error: "unknown skill type: #{skill[:type]}" }
          end
        end

        private

        def execute_prompt(skill, input: nil)
          return { success: false, error: 'Legion::LLM not available' } unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat_direct)

          prompt = skill[:prompt]
          prompt = "#{prompt}\n\nUser input: #{input}" if input

          session = Legion::LLM.chat_direct(model: skill[:model], provider: nil)
          response = session.ask(prompt)
          content = response.respond_to?(:content) ? response.content : response.to_s

          { success: true, output: content }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def execute_rb(skill, input: nil)
          begin
            real_path = File.realpath(skill[:path])
          rescue Errno::ENOENT
            return { success: false, error: "skill file not found: #{skill[:path]}" }
          end
          allowed = SKILL_DIRS.filter_map do |dir|
            expanded = File.expand_path(dir)
            File.realpath(expanded) if Dir.exist?(expanded)
          end
          unless allowed.any? { |dir| real_path.start_with?("#{dir}/") }
            return { success: false, error: "skill path outside allowed directories: #{real_path}" }
          end

          mod = Module.new
          mod.module_eval(File.read(real_path), real_path)
          return { success: false, error: "#{skill[:name]}.rb must define a module-level `self.call` method" } unless mod.respond_to?(:call)

          result = mod.call(input: input)
          { success: true, output: result }
        rescue StandardError => e
          { success: false, error: e.message }
        end
      end
    end
  end
end
