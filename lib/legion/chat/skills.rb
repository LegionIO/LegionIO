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

            Dir.glob(File.join(expanded, '*.md')).filter_map { |f| parse(f) }
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
            model:       frontmatter['model'],
            tools:       Array(frontmatter['tools']),
            prompt:      body,
            path:        path
          }
        rescue StandardError => e
          Legion::Logging.warn "Skill parse error #{path}: #{e.message}" if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
