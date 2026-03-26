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

      desc 'ingest [PATH...]', 'Ingest Claude memory/CLAUDE.md files into agentic memory traces'
      long_desc <<~DESC
        Parse Claude Code MEMORY.md or CLAUDE.md files and convert them into
        agentic memory traces for cold start bootstrapping.

        Accepts any number of file or directory paths. When given a directory,
        all CLAUDE.md and MEMORY.md files are discovered recursively.
        When no path is given, defaults to the current working directory.

        Use --dry-run to preview traces without storing them.
      DESC
      option :dry_run, type: :boolean, default: false, desc: 'Preview traces without storing'
      option :pattern, type: :string, default: '**/{CLAUDE,MEMORY}.md', desc: 'Glob pattern for directory mode'
      def ingest(*paths)
        out = formatter
        paths = [Dir.pwd] if paths.empty?

        paths.each do |path|
          unless File.exist?(path)
            out.error("Path not found: #{path}")
            next
          end

          if options[:dry_run]
            require_coldstart!
            run_local_ingest(out, path, dry_run: true)
            next
          end

          result = try_api_ingest(path)
          if result
            out.success('Ingested via running daemon (traces stored in live memory)')
            File.directory?(path) ? render_directory_result(out, result) : render_file_result(out, result)
          else
            out.warn('Daemon not running, ingesting locally (traces stored in-process only)')
            require_coldstart!
            run_local_ingest(out, path, dry_run: false)
          end
        end
      end
      default_task :ingest

      desc 'preview [PATH...]', 'Preview what traces would be created (alias for ingest --dry-run)'
      def preview(*paths)
        out = formatter
        require_coldstart!
        paths = [Dir.pwd] if paths.empty?

        runner = build_runner(Legion::Extensions::Coldstart::Runners::Ingest)

        paths.each do |path|
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
          end
        end
      end

      desc 'status', 'Show cold start progress'
      def status
        out = formatter
        require_coldstart!

        runner = build_runner(Legion::Extensions::Coldstart::Runners::Coldstart)
        progress = runner.coldstart_progress

        if options[:json]
          out.json(progress)
        else
          out.header('Cold Start Status')
          out.spacer
          out.detail({
                       'Firmware Loaded'   => progress[:firmware_loaded],
                       'Imprint Active'    => progress[:imprint_active],
                       'Imprint Progress'  => "#{(progress[:imprint_progress] * 100).round(1)}%",
                       'Observation Count' => progress[:observation_count],
                       'Calibration State' => progress[:calibration_state],
                       'Current Layer'     => progress[:current_layer]
                     })
        end
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        def run_local_ingest(out, path, dry_run:)
          runner = build_runner(Legion::Extensions::Coldstart::Runners::Ingest)

          if File.file?(path)
            result = dry_run ? runner.preview_ingest(file_path: File.expand_path(path)) : runner.ingest_file(file_path: File.expand_path(path))
            render_file_result(out, result)
          elsif File.directory?(path)
            result = runner.ingest_directory(
              dir_path:     File.expand_path(path),
              pattern:      options[:pattern] || '**/{CLAUDE,MEMORY}.md',
              store_traces: !dry_run
            )
            render_directory_result(out, result)
          end
        end

        def try_api_ingest(path)
          require 'net/http'
          require 'json'
          api_port = api_port_from_settings
          uri = URI("http://localhost:#{api_port}/api/coldstart/ingest")
          body = ::JSON.generate({ path: File.expand_path(path) })
          response = Net::HTTP.post(uri, body, 'Content-Type' => 'application/json')
          return nil unless response.is_a?(Net::HTTPSuccess)

          parsed = ::JSON.parse(response.body, symbolize_names: true)
          parsed[:data]
        rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, SocketError, Net::OpenTimeout => e
          Legion::Logging.debug("Coldstart#try_api_ingest daemon not reachable: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def api_port_from_settings
          require 'legion/settings'
          Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
          api_settings = Legion::Settings[:api]
          (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
        rescue StandardError => e
          Legion::Logging.warn("Coldstart#api_port_from_settings failed: #{e.message}") if defined?(Legion::Logging)
          4567
        end

        def build_runner(mod)
          obj = Object.new
          obj.extend(mod)
          obj.define_singleton_method(:log) { Legion::Logging } unless obj.respond_to?(:log)
          obj
        end

        def require_coldstart!
          require 'legion/logging'
          Legion::Logging.setup(level: options[:verbose] ? 'debug' : 'warn') unless Legion::Logging.instance_variable_get(:@log)

          begin
            require 'legion/extensions/agentic/memory/trace'
          rescue LoadError
            Legion::Logging.debug('lex-agentic-memory not available, traces will be parsed but not stored') if defined?(Legion::Logging)
          end

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
          out.detail({
                       'File'          => result[:file],
                       'Type'          => result[:file_type],
                       'Traces Parsed' => result[:traces_parsed] || result[:traces]&.size || 0,
                       'Traces Stored' => result[:traces_stored] || 0
                     })

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
          out.detail({
                       'Directory'    => result[:directory],
                       'Files Found'  => result[:files_found],
                       'Total Parsed' => result[:total_parsed],
                       'Total Stored' => result[:total_stored]
                     })

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
