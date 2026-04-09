# frozen_string_literal: true

require 'thor'
require 'json'
require 'legion/cli/output'
require 'legion/cli/error'
require 'legion/cli/connection'

module Legion
  module CLI
    class Notebook < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,                  desc: 'Config directory path'

      desc 'read PATH', 'Parse and display a Jupyter notebook with syntax highlighting'
      def read(path)
        out = formatter
        load_notebook(path, out)
        color = !options[:no_color]

        require 'legion/notebook/parser'
        require 'legion/notebook/renderer'

        parsed   = Legion::Notebook::Parser.parse(path)
        rendered = Legion::Notebook::Renderer.render_notebook(parsed, color: color)

        if options[:json]
          out.json(cells: parsed[:cells].length, kernel: parsed[:kernel], path: path)
        else
          puts rendered
          out.spacer
          count = parsed[:cells].length
          puts "#{count} cell#{'s' unless count == 1} total"
        end
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      end

      desc 'cells PATH', 'List all cells with index numbers and types'
      def cells(path)
        out = formatter
        load_notebook(path, out)

        require 'legion/notebook/parser'

        parsed = Legion::Notebook::Parser.parse(path)
        color  = !options[:no_color]

        if options[:json]
          cell_list = parsed[:cells].each_with_index.map do |cell, i|
            { index: i + 1, type: cell[:type], lines: cell[:source].lines.count }
          end
          out.json(cells: cell_list, total: parsed[:cells].length)
        else
          parsed[:cells].each_with_index do |cell, i|
            lines  = cell[:source].lines.count
            plural = lines == 1 ? '' : 's'
            label  = "  [#{(i + 1).to_s.rjust(2)}] #{cell[:type].to_s.ljust(8)}  #{lines} line#{plural}"
            if color
              type_color = cell[:type] == 'code' ? "\e[36m" : "\e[33m"
              puts "#{type_color}#{label}\e[0m"
            else
              puts label
            end
          end
          out.spacer
          puts "Total: #{parsed[:cells].length} cell#{'s' unless parsed[:cells].length == 1}"
        end
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      end

      desc 'export PATH', 'Export notebook to another format'
      option :format, type: :string, default: 'md', enum: %w[md markdown script], desc: 'Export format: md or script'
      option :output, type: :string, aliases: ['-o'], desc: 'Write to file instead of stdout'
      def export(path)
        out = formatter
        load_notebook(path, out)

        require 'legion/notebook/parser'

        parsed = Legion::Notebook::Parser.parse(path)
        lang   = parsed[:language]

        content = case options[:format]
                  when 'script'
                    export_as_script(parsed[:cells], lang)
                  else
                    export_as_markdown(parsed[:cells], lang)
                  end

        if options[:output]
          File.write(options[:output], content)
          out.success("Exported to #{options[:output]}")
        elsif options[:json]
          out.json(content: content, format: options[:format], path: path)
        else
          puts content
        end
      rescue CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      end

      desc 'create PATH', 'Generate a Jupyter notebook from a natural language description (requires legion-llm)'
      option :description, type: :string, aliases: ['-d'], desc: 'What the notebook should do'
      option :kernel,      type: :string, default: 'python3', desc: 'Kernel name (default: python3)'
      option :model,       type: :string, aliases: ['-m'], desc: 'LLM model override'
      option :provider,    type: :string, desc: 'LLM provider override'
      def create(path)
        out = formatter
        setup_llm_connection(out)

        require 'legion/notebook/generator'

        description = options[:description]
        if description.nil? || description.strip.empty?
          out.error('--description is required for notebook creation')
          raise SystemExit, 1
        end

        out.success("Generating notebook: #{description}") unless options[:json]

        notebook_data = Legion::Notebook::Generator.generate(
          description: description,
          kernel:      options[:kernel],
          model:       options[:model],
          provider:    options[:provider]
        )

        Legion::Notebook::Generator.write(path, notebook_data)
        cell_count = Array(notebook_data['cells']).length

        if options[:json]
          out.json(path: path, cells: cell_count, kernel: options[:kernel])
        else
          out.success("Created #{path} (#{cell_count} cells)")
        end
      rescue ArgumentError, CLI::Error => e
        formatter.error(e.message)
        raise SystemExit, 1
      ensure
        Connection.shutdown
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def setup_llm_connection(out)
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level  = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_llm
        rescue CLI::Error => e
          out.error(e.message)
          raise SystemExit, 1
        end

        def load_notebook(path, out)
          unless File.exist?(path)
            out.error("File not found: #{path}")
            raise SystemExit, 1
          end

          unless path.end_with?('.ipynb')
            out.error("Expected a .ipynb file, got: #{File.basename(path)}")
            raise SystemExit, 1
          end

          ::JSON.parse(File.read(path))
        rescue ::JSON::ParserError => e
          out.error("Invalid notebook JSON: #{e.message}")
          raise SystemExit, 1
        end

        def export_as_markdown(cells, lang)
          lines = []
          cells.each do |cell|
            if cell[:type] == 'code'
              lines << "```#{lang}"
              lines << cell[:source]
              lines << '```'
            else
              lines << cell[:source]
            end
            lines << ''
          end
          lines.join("\n")
        end

        def export_as_script(cells, _lang)
          lines = []
          cells.each do |cell|
            if cell[:type] == 'code'
              lines << cell[:source]
            else
              cell[:source].each_line do |line|
                lines << "# #{line.chomp}"
              end
            end
            lines << ''
          end
          lines.join("\n")
        end
      end
    end
  end
end
