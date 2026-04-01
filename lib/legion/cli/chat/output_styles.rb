# frozen_string_literal: true

require 'yaml'

module Legion
  module CLI
    class Chat
      module OutputStyles
        STYLE_DIRS = ['.legionio/output-styles', '~/.legionio/output-styles'].freeze

        class << self
          def discover
            STYLE_DIRS.flat_map do |dir|
              expanded = File.expand_path(dir)
              next [] unless Dir.exist?(expanded)

              Dir.glob(File.join(expanded, '*.md')).filter_map { |f| parse(f) }
            end
          end

          def active_styles
            discover.select { |s| s[:active] }
          end

          def find(name)
            discover.find { |s| s[:name] == name.to_s }
          end

          def activate(name)
            style = find(name)
            return nil unless style

            path = style[:path]
            content = File.read(path)
            content.sub!(/^---\s*$/, "---\nactive: true") unless content.match?(/^active:\s/)
            content.gsub!(/^active:\s+\w+/, 'active: true')
            File.write(path, content)
            style[:name]
          end

          def system_prompt_injection
            active = active_styles
            return nil if active.empty?

            active.map { |s| s[:content] }.join("\n\n")
          end

          def parse(path)
            raw = File.read(path)
            return nil unless raw.start_with?('---')

            parts = raw.split(/^---\s*$/, 3)
            return nil if parts.size < 3

            frontmatter = YAML.safe_load(parts[1], permitted_classes: [Symbol])
            body = parts[2]&.strip

            {
              name:        frontmatter['name'] || File.basename(path, '.md'),
              description: frontmatter['description'] || '',
              active:      frontmatter['active'] == true,
              content:     body,
              path:        path
            }
          rescue StandardError => e
            Legion::Logging.warn "OutputStyles parse error #{path}: #{e.message}" if defined?(Legion::Logging)
            nil
          end
        end
      end
    end
  end
end
