# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Notebook < Thor
      def self.exit_on_failure?
        true
      end

      desc 'read PATH', 'Read and display a Jupyter notebook'
      def read(path)
        nb = parse_notebook(path)
        cells = nb['cells'] || []

        cells.each_with_index do |cell, i|
          type = cell['cell_type'] || 'unknown'
          source = Array(cell['source']).join
          say "--- Cell #{i + 1} [#{type}] ---", :yellow
          say source
          say ''
        end
        say "#{cells.size} cells total", :green
      end

      desc 'export PATH', 'Export notebook cells as markdown or script'
      option :format, type: :string, default: 'markdown', enum: %w[markdown script]
      def export(path)
        nb = parse_notebook(path)
        cells = nb['cells'] || []
        lang = nb.dig('metadata', 'kernelspec', 'language') || 'python'

        case options[:format]
        when 'script'
          cells.select { |c| c['cell_type'] == 'code' }.each do |cell|
            say Array(cell['source']).join
            say ''
          end
        else
          cells.each do |cell|
            if cell['cell_type'] == 'code'
              say "```#{lang}"
              say Array(cell['source']).join
              say '```'
            else
              say Array(cell['source']).join
            end
            say ''
          end
        end
      end

      private

      def parse_notebook(path)
        unless File.exist?(path)
          say "File not found: #{path}", :red
          raise SystemExit, 1
        end

        ::JSON.parse(File.read(path))
      rescue ::JSON::ParserError => e
        say "Invalid notebook format: #{e.message}", :red
        raise SystemExit, 1
      end
    end
  end
end
