require_relative 'readiness'

module Legion
  class Service
    def modules
      [Legion::Crypt, Legion::Transport, Legion::Cache, Legion::Data, Legion::Supervision].freeze
    end

    def initialize(transport: true, cache: true, data: true, supervision: true, extensions: true, crypt: true, log_level: 'info') # rubocop:disable Metrics/ParameterLists
      setup_logging(log_level: log_level)
      Legion::Logging.debug('Starting Legion::Service')
      setup_settings
      Legion::Logging.info("node name: #{Legion::Settings[:client][:name]}")

      if crypt
        require 'legion/crypt'
        Legion::Crypt.start
        Legion::Readiness.mark_ready(:crypt)
      end

      if transport
        setup_transport
        Legion::Readiness.mark_ready(:transport)
      end

      if cache
        require 'legion/cache'
        Legion::Readiness.mark_ready(:cache)
      end

      if data
        setup_data
        Legion::Readiness.mark_ready(:data)
      end

      setup_supervision if supervision

      if extensions
        load_extensions
        Legion::Readiness.mark_ready(:extensions)
      end

      Legion::Crypt.cs if crypt
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
    end

    def setup_data
      require 'legion/data'
      Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
      Legion::Data.setup
    rescue LoadError
      Legion::Logging.info 'Legion::Data gem is not installed, please install it manually with gem install legion-data'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Data failed to load, starting without it. e: #{e.message}"
    end

    # noinspection RubyArgCount
    def default_paths
      [
        '/etc/legionio',
        "#{ENV['home']}/legionio",
        '~/legionio',
        './settings'
      ]
    end

    def setup_settings(default_dir = __dir__)
      require 'legion/settings'
      config_directory = default_dir
      default_paths.each do |path|
        next unless Dir.exist? path

        Legion::Logging.info "Using #{path} for settings"
        config_directory = path
        break
      end

      Legion::Logging.info "Using directory #{config_directory} for settings"
      Legion::Settings.load(config_dir: config_directory)
      Legion::Readiness.mark_ready(:settings)
      Legion::Logging.info('Legion::Settings Loaded')
    end

    def setup_logging(log_level: 'info', **_opts)
      require 'legion/logging'
      Legion::Logging.setup(log_level: log_level, level: log_level, trace: true)
    end

    def setup_transport
      require 'legion/transport'
      Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
      Legion::Transport::Connection.setup
    end

    def setup_supervision
      require 'legion/supervision'
      @supervision = Legion::Supervision.setup
    end

    def shutdown
      Legion::Logging.info('Legion::Service.shutdown was called')
      @shutdown = true
      Legion::Settings[:client][:shutting_down] = true
      Legion::Events.emit('service.shutting_down')

      Legion::Extensions.shutdown
      Legion::Readiness.mark_not_ready(:extensions)

      Legion::Data.shutdown if Legion::Settings[:data][:connected]
      Legion::Readiness.mark_not_ready(:data)

      Legion::Cache.shutdown
      Legion::Readiness.mark_not_ready(:cache)

      Legion::Transport::Connection.shutdown
      Legion::Readiness.mark_not_ready(:transport)

      Legion::Crypt.shutdown
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Settings[:client][:ready] = false
      Legion::Events.emit('service.shutdown')
    end

    def reload
      Legion::Logging.info 'Legion::Service.reload was called'
      Legion::Settings[:client][:ready] = false

      Legion::Extensions.shutdown
      Legion::Readiness.mark_not_ready(:extensions)

      Legion::Data.shutdown
      Legion::Readiness.mark_not_ready(:data)

      Legion::Cache.shutdown
      Legion::Readiness.mark_not_ready(:cache)

      Legion::Transport::Connection.shutdown
      Legion::Readiness.mark_not_ready(:transport)

      Legion::Crypt.shutdown
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Readiness.wait_until_not_ready(:transport, :data, :cache, :crypt)

      setup_settings
      Legion::Crypt.start
      Legion::Readiness.mark_ready(:crypt)

      setup_transport
      Legion::Readiness.mark_ready(:transport)

      setup_data
      Legion::Readiness.mark_ready(:data)

      setup_supervision

      load_extensions
      Legion::Readiness.mark_ready(:extensions)

      Legion::Crypt.cs
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
      Legion::Logging.info 'Legion has been reloaded'
    end

    def load_extensions
      require 'legion/runner'
      Legion::Extensions.hook_extensions
    end
  end
end
