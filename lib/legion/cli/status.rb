# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Legion
  module CLI
    module Status
      class << self
        def run(out, options)
          # Try the HTTP API first (running service)
          api_status = check_api(options)

          if api_status
            show_running(out, api_status, options)
          else
            show_static(out, options)
          end
        end

        private

        def check_api(options)
          port = options[:port] || 4567
          host = options[:host] || '127.0.0.1'

          uri = URI("http://#{host}:#{port}/ready")
          response = Net::HTTP.get_response(uri)
          JSON.parse(response.body, symbolize_names: true)
        rescue StandardError
          nil
        end

        def show_running(out, api_status, options)
          if options[:json]
            out.json(running: true, **api_status)
            return
          end

          ready = api_status[:ready]
          out.header('Legion Service')
          puts "  #{out.colorize('STATUS:', :cyan)} #{ready ? out.colorize('RUNNING', :green) : out.colorize('STARTING', :yellow)}"
          out.spacer

          if api_status[:components]
            out.header('Components')
            api_status[:components].each do |component, is_ready|
              status_str = is_ready ? out.colorize('ready', :green) : out.colorize('not ready', :yellow)
              puts "  #{component.to_s.ljust(15)} #{status_str}"
            end
          end

          # Check for PID
          pidfile = find_pidfile
          return unless pidfile

          pid = File.read(pidfile).to_i
          out.spacer
          puts "  #{out.colorize('PID:', :cyan)} #{pid} (#{pidfile})"
        end

        def show_static(out, options)
          if options[:json]
            out.json(
              running:      false,
              extensions:   discovered_lexs,
              config_paths: config_paths
            )
            return
          end

          out.header('Legion Service')
          puts "  #{out.colorize('STATUS:', :cyan)} #{out.colorize('NOT RUNNING', :red)}"
          out.spacer

          lexs = discovered_lexs
          out.header("Installed Extensions (#{lexs.size})")
          lexs.each do |name, version|
            puts "  #{out.colorize(name.ljust(20), :cyan)} #{version}"
          end

          out.spacer
          out.header('Config Search Paths')
          config_paths.each do |path|
            exists = Dir.exist?(path)
            marker = exists ? out.colorize('*', :green) : out.colorize(' ', :gray)
            path_str = exists ? path : out.colorize(path, :gray)
            puts "  #{marker} #{path_str}"
          end
        end

        def discovered_lexs
          Gem::Specification.select { |s| s.name.start_with?('lex-') }
                            .map { |s| [s.name, s.version.to_s] }
                            .sort_by(&:first)
        end

        def config_paths
          [
            '/etc/legionio',
            File.expand_path('~/legionio'),
            './settings'
          ]
        end

        def find_pidfile
          %w[/var/run/legion.pid /tmp/legion.pid].find { |f| File.exist?(f) }
        end
      end
    end
  end
end
