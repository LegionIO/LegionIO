# frozen_string_literal: true

module Legion
  module CLI
    class Telemetry < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'

      desc 'stats [SESSION_ID]', 'Show telemetry stats (aggregate or per-session)'
      def stats(session_id = nil)
        out    = formatter
        runner = telemetry_runner

        result = if session_id
                   runner.session_stats(session_id: session_id)
                 else
                   runner.aggregate_stats
                 end

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header(session_id ? "Session: #{session_id}" : 'Aggregate Telemetry Stats')
          display_stats(out, result[:stats])
        else
          out.error("Error: #{result[:error]}")
        end
      end
      default_task :stats

      desc 'ingest PATH', 'Manually ingest a session log file'
      def ingest(path)
        out    = formatter
        runner = telemetry_runner
        result = runner.ingest_session(file_path: path)

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.success("Ingested #{result[:event_count]} events from #{path}")
          out.detail({ session_id: result[:session_id], events: result[:event_count] })
        else
          out.error("Error: #{result[:error]}")
        end
      end

      desc 'status', 'Show telemetry buffer health and publisher state'
      def status
        out    = formatter
        runner = telemetry_runner
        result = runner.telemetry_status

        if options[:json]
          out.json(result)
        elsif result[:success]
          out.header('Telemetry Status')
          out.detail({
                       'Buffer Size' => result[:buffer_size].to_s,
                       'Pending'     => result[:pending_count].to_s,
                       'Sessions'    => result[:session_count].to_s,
                       'Parsers'     => result[:parsers].join(', ')
                     })
        else
          out.error("Error: #{result[:error]}")
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def telemetry_runner
          require 'legion/extensions/telemetry/runners/telemetry'
          Legion::Extensions::Telemetry::Runners::Telemetry
        end

        def display_stats(out, stats)
          return unless stats

          stats.each do |key, value|
            case value
            when Hash
              out.spacer
              out.header(key.to_s)
              value.each { |k, v| puts "  #{k}: #{v}" }
            else
              puts "  #{key}: #{value}"
            end
          end
        end
      end
    end
  end
end
