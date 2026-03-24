# frozen_string_literal: true

module Legion
  module CLI
    module Start
      class << self
        def run(options)
          if options[:lite]
            ENV['LEGION_MODE'] = 'lite'
            ENV['LEGION_LOCAL'] = 'true'
          end

          log_level = options[:log_level] || 'info'

          # Load settings early, before any legion-* gem requires can trigger auto-load.
          # This ensures DNS bootstrap and config file loading happen exactly once.
          require 'legion/json'
          require 'legion/settings'
          directories = Legion::Settings::Loader.default_directories.select { |d| Dir.exist?(d) }
          Legion::Settings.load(config_dirs: directories)

          require 'legion'
          require 'legion/service'
          require 'legion/process'

          clear_log_file unless options[:daemonize]

          api = options.fetch(:api, true)
          service_opts = { log_level: log_level, api: api }
          service_opts[:http_port] = options[:http_port] if options[:http_port]
          service_opts[:role] = :lite if options[:lite]
          Legion.instance_variable_set(:@service, Legion::Service.new(**service_opts))
          Legion::Logging.info("Started Legion v#{Legion::VERSION}")

          process_opts = {
            daemonize:  options[:daemonize],
            pidfile:    options[:pidfile],
            logfile:    options[:logfile],
            time_limit: options[:time_limit]
          }.compact

          Legion::Process.new(process_opts).run!
        end

        private

        def clear_log_file
          logging = Legion::Settings[:logging]
          return unless logging.is_a?(Hash) && logging[:log_file]

          path = File.expand_path(logging[:log_file])
          return unless File.exist?(path)

          File.truncate(path, 0)
        rescue StandardError => e
          Legion::Logging.warn("Start#clear_log_file failed: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end
    end
  end
end
