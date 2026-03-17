# frozen_string_literal: true

require 'fileutils'

module Legion
  module Docs
    class SiteGenerator
      SECTIONS = [
        { source: 'docs/getting-started.md', title: 'Getting Started' },
        { source: 'docs/overview.md', title: 'Architecture' },
        { source: 'docs/extension-development.md', title: 'Extension Development' },
        { source: 'docs/best-practices.md', title: 'Best Practices' },
        { source: 'docs/protocol.md', title: 'Protocol' }
      ].freeze

      def initialize(output_dir: 'docs/site')
        @output_dir = output_dir
      end

      def generate
        FileUtils.mkdir_p(@output_dir)
        generate_index
        copy_sections
        { output: @output_dir, sections: SECTIONS.size }
      end

      private

      def generate_index
        content = "# LegionIO Documentation\n\n"
        SECTIONS.each do |section|
          slug = File.basename(section[:source], '.md')
          content += "- [#{section[:title]}](#{slug}.md)\n"
        end
        File.write(File.join(@output_dir, 'index.md'), content)
      end

      def copy_sections
        SECTIONS.each do |section|
          src = section[:source]
          next unless File.exist?(src)

          FileUtils.cp(src, File.join(@output_dir, File.basename(src)))
        end
      end
    end
  end
end
