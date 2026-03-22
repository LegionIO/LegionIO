# frozen_string_literal: true

require 'net/http'
require 'json'

module Legion
  module CLI
    class Gaia < Thor
      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'

      desc 'status', 'Show GAIA cognitive coordination status'
      option :port, type: :numeric, default: 4567, desc: 'API port'
      option :host, type: :string,  default: '127.0.0.1', desc: 'API host'
      def status
        out  = formatter
        data = probe_api

        if data.nil?
          show_not_running(out)
        elsif options[:json]
          out.json(data)
        else
          show_status(out, data)
        end
      end
      default_task :status

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def probe_api
          host = options[:host] || '127.0.0.1'
          port = options[:port] || api_port
          uri  = URI("http://#{host}:#{port}/api/gaia/status")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 3
          http.read_timeout = 5
          response = http.get(uri.path)
          parsed   = ::JSON.parse(response.body, symbolize_names: true)
          parsed[:data] || parsed
        rescue StandardError => e
          Legion::Logging.warn("GaiaCommand#probe_api failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end

        def api_port
          require 'legion/settings'
          Legion::Settings.load unless Legion::Settings.instance_variable_get(:@loader)
          api_settings = Legion::Settings[:api]
          (api_settings.is_a?(Hash) && api_settings[:port]) || 4567
        rescue StandardError => e
          Legion::Logging.warn("GaiaCommand#api_port failed: #{e.message}") if defined?(Legion::Logging)
          4567
        end

        def show_not_running(out)
          if options[:json]
            out.json({ started: false, error: 'daemon not running' })
          else
            out.header('GAIA Status')
            out.warn('Legion daemon not running (connection refused)')
          end
        end

        def show_status(out, data)
          out.header('GAIA Status')
          details = {
            'Mode'       => (data[:mode] || 'unknown').to_s,
            'Started'    => data[:started].to_s,
            'Buffer'     => (data[:buffer_depth] || 0).to_s,
            'Sessions'   => (data[:sessions] || 0).to_s,
            'Extensions' => "#{data[:extensions_loaded]}/#{data[:extensions_total]} loaded",
            'Phases'     => "#{data[:wired_phases]} wired"
          }
          out.detail(details)

          channels = data[:active_channels] || []
          out.spacer
          out.header("Active Channels (#{channels.size})")
          channels.each { |ch| puts "  #{ch}" }

          phases = data[:phase_list] || []
          return if phases.empty?

          out.spacer
          out.header("Wired Phases (#{phases.size})")
          puts "  #{phases.join(', ')}"
        end
      end
    end
  end
end
