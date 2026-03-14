# frozen_string_literal: true

module Legion
  module CLI
    class Coldstart < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,     type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,  type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'

      desc 'ingest PATH', 'Ingest Claude memory/CLAUDE.md files into lex-memory traces'
      long_desc <<~DESC
        Parse Claude Code MEMORY.md or CLAUDE.md files and convert them into
        lex-memory traces for cold start bootstrapping.

        PATH can be a single file or a directory. When given a directory,
        all CLAUDE.md and MEMORY.md files are discovered recursively.

        Use --dry-run to preview traces without storing them.
      DESC
      option :dry_run, type: :boolean, default: false, desc: 'Preview traces without storing'
      option :pattern, type: :string, default: '**/{CLAUDE,MEMORY}.md', desc: 'Glob pattern for directory mode'
      def ingest(path)
        out = formatter
        require_coldstart!

        runner = Object.new.extend(Legion::Extensions::Coldstart::Runners::Ingest)

        if File.file?(path)
          result = if options[:dry_run]
                     runner.preview_ingest(file_path: File.expand_path(path))
                   else
                     runner.ingest_file(file_path: File.expand_path(path))
                   end
          render_file_result(out, result)
        elsif File.directory?(path)
          result = runner.ingest_directory(
            dir_path:     File.expand_path(path),
            pattern:      options[:pattern],
            store_traces: !options[:dry_run]
          )
          render_directory_result(out, result)
        else
          out.error("Path not found: #{path}")
          raise SystemExit, 1
        end
      end
      default_task :ingest

      desc 'preview PATH', 'Preview what traces would be created (alias for ingest --dry-run)'
      def preview(path)
        out = formatter
        require_coldstart!

        runner = Object.new.extend(Legion::Extensions::Coldstart::Runners::Ingest)

        if File.file?(path)
          result = runner.preview_ingest(file_path: File.expand_path(path))
          render_file_result(out, result)
        elsif File.directory?(path)
          result = runner.ingest_directory(
            dir_path:     File.expand_path(path),
            pattern:      '**/{CLAUDE,MEMORY}.md',
            store_traces: false
          )
          render_directory_result(out, result)
        else
          out.error("Path not found: #{path}")
          raise SystemExit, 1
        end
      end

      desc 'status', 'Show cold start progress'
      def status
        out = formatter
        require_coldstart!

        runner = Object.new.extend(Legion::Extensions::Coldstart::Runners::Coldstart)
        progress = runner.coldstart_progress

        if options[:json]
          out.json(progress)
        else
          out.header('Cold Start Status')
          out.spacer
          out.detail(
            'Firmware Loaded'    => progress[:firmware_loaded],
            'Imprint Active'     => progress[:imprint_active],
            'Imprint Progress'   => "#{(progress[:imprint_progress] * 100).round(1)}%",
            'Observation Count'  => progress[:observation_count],
            'Calibration State'  => progress[:calibration_state],
            'Current Layer'      => progress[:current_layer]
          )
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def require_coldstart!
          require 'legion/extensions/coldstart'
        rescue LoadError => e
          formatter.error("lex-coldstart not available: #{e.message}")
          raise SystemExit, 1
        end

        def render_file_result(out, result)
          if result[:error]
            out.error(result[:error])
            raise SystemExit, 1
          end

          if options[:json]
            out.json(result)
            return
          end

          out.header("Ingested: #{File.basename(result[:file] || result[:file_path] || 'unknown')}")
          out.spacer
          out.detail(
            'File'          => result[:file],
            'Type'          => result[:file_type],
            'Traces Parsed' => result[:traces_parsed] || result[:traces]&.size || 0,
            'Traces Stored' => result[:traces_stored] || 0
          )

          traces = result[:traces] || []
          return if traces.empty?

          out.spacer
          type_counts = traces.group_by { |t| t[:trace_type] }.transform_values(&:size)
          out.header('Trace Types')
          type_counts.sort_by { |_, v| -v }.each do |type, count|
            puts "  #{out.colorize(type.to_s.ljust(15), :cyan)} #{count}"
          end
        end

        def render_directory_result(out, result)
          if result[:error]
            out.error(result[:error])
            raise SystemExit, 1
          end

          if options[:json]
            out.json(result)
            return
          end

          out.header("Directory Ingest: #{result[:directory]}")
          out.spacer
          out.detail(
            'Directory'     => result[:directory],
            'Files Found'   => result[:files_found],
            'Total Parsed'  => result[:total_parsed],
            'Total Stored'  => result[:total_stored]
          )

          files = result[:files] || []
          return if files.empty?

          out.spacer
          out.header('Files Processed')
          files.each { |f| puts "  #{f}" }
        end
      end
    end
  end
end
