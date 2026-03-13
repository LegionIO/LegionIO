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

          Legion::Service.new(log_level: log_level)
          Legion::Logging.info("Started Legion v#{Legion::VERSION}")

          process_opts = {
            daemonize:  options[:daemonize],
            pidfile:    options[:pidfile],
            logfile:    options[:logfile],
            time_limit: options[:time_limit]
          }.compact

          Legion::Process.new(process_opts).run!
        end
      end
    end
  end
end
