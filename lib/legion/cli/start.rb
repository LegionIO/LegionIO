# frozen_string_literal: true

module Legion
  module CLI
    module Start
      class << self
        def run(options)
          log_level = options[:log_level] || 'info'

          require 'legion'
          require 'legion/service'
          require 'legion/process'

          clear_log_file unless options[:daemonize]

          api = options.fetch(:api, true)
          service_opts = { log_level: log_level, api: api }
          service_opts[:http_port] = options[:http_port] if options[:http_port]
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
          require 'legion/settings'
          Legion::Settings.load
          logging = Legion::Settings[:logging]
          return unless logging.is_a?(Hash) && logging[:log_file]

          path = File.expand_path(logging[:log_file])
          return unless File.exist?(path)

          File.truncate(path, 0)
        rescue StandardError
          nil
        end
      end
    end
  end
end
