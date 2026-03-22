# frozen_string_literal: true

require_relative 'readiness'
require_relative 'process_role'

module Legion
  class Service
    def modules
      base = [Legion::Crypt, Legion::Transport, Legion::Cache, Legion::Data, Legion::Supervision]
      base << Legion::LLM if defined?(Legion::LLM)
      base << Legion::Gaia if defined?(Legion::Gaia)
      base.freeze
    end

    def initialize(transport: nil, cache: nil, data: nil, supervision: nil, extensions: nil, # rubocop:disable Metrics/CyclomaticComplexity,Metrics/ParameterLists,Metrics/MethodLength,Metrics/PerceivedComplexity,Metrics/AbcSize
                   crypt: nil, api: nil, llm: nil, gaia: nil, log_level: 'info', http_port: nil,
                   role: nil)
      role_opts = Legion::ProcessRole.resolve(role || Legion::ProcessRole.current)
      transport  = role_opts[:transport] if transport.nil?
      cache      = role_opts[:cache] if cache.nil?
      data       = role_opts[:data] if data.nil?
      supervision = role_opts[:supervision] if supervision.nil?
      extensions = role_opts[:extensions] if extensions.nil?
      crypt      = role_opts[:crypt] if crypt.nil?
      api        = role_opts[:api] if api.nil?
      llm        = role_opts[:llm] if llm.nil?
      gaia       = role_opts[:gaia] if gaia.nil?

      setup_logging(log_level: log_level)
      Legion::Logging.debug('Starting Legion::Service')
      setup_settings
      apply_cli_overrides(http_port: http_port)
      setup_local_mode
      reconfigure_logging(log_level)
      Legion::Logging.info("node name: #{Legion::Settings[:client][:name]}")

      if crypt
        require 'legion/crypt'
        Legion::Crypt.start
        Legion::Readiness.mark_ready(:crypt)
      end

      Legion::Settings.resolve_secrets!

      if transport
        setup_transport
        Legion::Readiness.mark_ready(:transport)
        register_logging_hooks
      end

      if cache
        require 'legion/cache'
        Legion::Cache.setup
        Legion::Readiness.mark_ready(:cache)
      end

      if data
        setup_data
        Legion::Readiness.mark_ready(:data)
      end

      setup_rbac if data

      if llm
        setup_llm
        Legion::Readiness.mark_ready(:llm)
      end

      if gaia
        setup_gaia
        Legion::Readiness.mark_ready(:gaia)
      end

      setup_telemetry
      setup_safety_metrics
      setup_supervision if supervision

      if extensions
        load_extensions
        Legion::Readiness.mark_ready(:extensions)
      end

      Legion::Gaia.registry&.rediscover if gaia && defined?(Legion::Gaia) && Legion::Gaia.started?

      Legion::Extensions::Memory::Helpers::ErrorTracer.setup if defined?(Legion::Extensions::Memory::Helpers::ErrorTracer)

      Legion::Crypt.cs if crypt

      setup_alerts
      setup_metrics

      api_settings = Legion::Settings[:api] || {}
      @api_enabled = api && api_settings.fetch(:enabled, true)
      setup_api if @api_enabled
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
    end

    def setup_local_mode
      return unless local_mode?

      Legion::Logging.info 'Starting in local development mode'
      Legion::Settings[:dev] = true

      require 'legion/transport/local'
      require 'legion/crypt/mock_vault'
    end

    def local_mode?
      ENV['LEGION_LOCAL'] == 'true' ||
        Legion::Settings[:local_mode] == true
    end

    def setup_data
      Legion::Logging.info 'Setting up Legion::Data'
      require 'legion/data'
      Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
      Legion::Data.setup
      Legion::Logging.info 'Legion::Data connected'
    rescue LoadError
      Legion::Logging.info 'Legion::Data gem is not installed, please install it manually with gem install legion-data'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Data failed to load, starting without it. e: #{e.message}"
    end

    def setup_rbac
      require 'legion/rbac'
      Legion::Rbac.setup
      Legion::Readiness.mark_ready(:rbac)
      Legion::Logging.info 'Legion::Rbac loaded'
    rescue LoadError
      Legion::Logging.debug 'Legion::Rbac gem is not installed, starting without RBAC'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Rbac failed to load: #{e.message}"
    end

    # noinspection RubyArgCount
    def default_paths
      [
        '/etc/legionio',
        "#{Dir.home}/.legionio/settings",
        "#{ENV.fetch('home', nil)}/legionio",
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
      self.class.log_privacy_mode_status
    end

    def apply_cli_overrides(http_port: nil)
      return unless http_port

      Legion::Settings[:api] ||= {}
      Legion::Settings[:api][:port] = http_port
      Legion::Logging.info "CLI override: API port set to #{http_port}"
    end

    def setup_logging(log_level: 'info', **_opts)
      require 'legion/logging'
      Legion::Logging.setup(log_level: log_level, level: log_level, trace: true)
    end

    def reconfigure_logging(cli_level)
      logging_settings = Legion::Settings[:logging] || {}
      level = cli_level || logging_settings[:level] || 'info'
      Legion::Logging.setup(
        level:      level,
        log_file:   logging_settings[:log_file],
        log_stdout: logging_settings[:log_stdout],
        trace:      logging_settings.fetch(:trace, true)
      )
    end

    def setup_api
      require 'legion/api'
      api_settings = Legion::Settings[:api] || {}
      port = api_settings[:port] || 4567
      bind = api_settings[:bind] || '0.0.0.0'

      @api_thread = Thread.new do
        retries = 0
        max_retries = api_settings.fetch(:bind_retries, 10)
        retry_wait = api_settings.fetch(:bind_retry_wait, 3)

        begin
          Legion::API.set :port, port
          Legion::API.set :bind, bind
          Legion::API.set :server, :puma
          Legion::API.set :environment, :production
          require 'puma'
          puma_log = ::Puma::LogWriter.new(StringIO.new, StringIO.new)
          Legion::API.set :server_settings, { log_writer: puma_log, quiet: true }
          Legion::Logging.info "Starting Legion API on #{bind}:#{port}"
          Legion::API.run!(traps: false)
        rescue Errno::EADDRINUSE
          retries += 1
          if retries <= max_retries
            Legion::Logging.warn "Port #{port} in use, retrying in #{retry_wait}s (attempt #{retries}/#{max_retries})"
            sleep retry_wait
            retry
          else
            Legion::Logging.error "Port #{port} still in use after #{max_retries} attempts, API disabled"
            Legion::Readiness.mark_not_ready(:api)
          end
        end
      end
      Legion::Readiness.mark_ready(:api)
    rescue LoadError => e
      Legion::Logging.warn "Legion API dependencies not available: #{e.message}"
    rescue StandardError => e
      Legion::Logging.warn "Legion API failed to start: #{e.message}"
    end

    def setup_llm
      Legion::Logging.info 'Setting up Legion::LLM'
      require 'legion/llm'
      Legion::Settings.merge_settings('llm', Legion::LLM::Settings.default)
      Legion::LLM.start
      Legion::Logging.info 'Legion::LLM started'
    rescue LoadError
      Legion::Logging.info 'Legion::LLM gem is not installed, starting without LLM support'
    rescue StandardError => e
      Legion::Logging.warn "Legion::LLM failed to load: #{e.message}"
    end

    def setup_gaia
      Legion::Logging.info 'Setting up Legion::Gaia'
      require 'legion/gaia'
      Legion::Settings.merge_settings('gaia', Legion::Gaia::Settings.default)
      Legion::Gaia.boot
      Legion::Logging.info 'Legion::Gaia booted'
    rescue LoadError
      Legion::Logging.info 'Legion::Gaia gem is not installed, starting without cognitive layer'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Gaia failed to load: #{e.message}"
    end

    def setup_transport
      Legion::Logging.info 'Setting up Legion::Transport'
      require 'legion/transport'
      Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
      Legion::Transport::Connection.setup
      Legion::Logging.info 'Legion::Transport connected'
    end

    def register_logging_hooks
      return unless Legion::Transport::Connection.session_open?

      require 'legion/transport/exchanges/logging' unless defined?(Legion::Transport::Exchanges::Logging)
      exchange = Legion::Transport::Exchanges::Logging.new

      %i[fatal error warn].each do |level|
        Legion::Logging.send(:"on_#{level}") do |event|
          next unless Legion::Transport::Connection.session_open?

          source = event[:lex] || 'core'
          routing_key = "legion.#{source}.#{level}"
          exchange.publish(Legion::JSON.dump(event), routing_key: routing_key)
        rescue StandardError
          nil
        end
      end

      Legion::Logging.enable_hooks!
      Legion::Logging.info('Logging hooks registered for RMQ publishing')
    end

    def setup_alerts
      enabled = begin
        Legion::Settings[:alerts][:enabled]
      rescue StandardError
        false
      end
      return unless enabled

      require 'legion/alerts'
      Legion::Alerts.setup
    rescue StandardError => e
      Legion::Logging.warn "Alerts setup failed: #{e.message}"
    end

    def setup_metrics
      require 'legion/metrics'
      Legion::Metrics.setup
      Legion::Logging.debug 'Legion::Metrics initialized'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Metrics setup failed: #{e.message}"
    end

    def setup_telemetry
      return unless begin
        Legion::Settings.dig(:telemetry, :enabled)
      rescue StandardError
        false
      end

      require 'opentelemetry/sdk'
      require 'opentelemetry-exporter-otlp'
      require_relative 'telemetry'

      endpoint = Legion::Settings.dig(:telemetry, :otlp_endpoint) || 'http://localhost:4318'
      service_name = "legion-#{Legion::Settings[:client][:name]}"

      OpenTelemetry::SDK.configure do |c|
        c.service_name = service_name
        c.service_version = Legion::VERSION
        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
            OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: endpoint)
          )
        )
      end

      Legion::Logging.info "OpenTelemetry initialized: endpoint=#{endpoint} service=#{service_name}"
    rescue LoadError
      Legion::Logging.info 'OpenTelemetry gems not installed, starting without telemetry'
    rescue StandardError => e
      Legion::Logging.warn "OpenTelemetry setup failed: #{e.message}"
    end

    def setup_safety_metrics
      require_relative 'telemetry/safety_metrics'
      Legion::Telemetry::SafetyMetrics.start
    rescue LoadError
      nil
    rescue StandardError => e
      Legion::Logging.debug "[safety_metrics] setup skipped: #{e.message}" if defined?(Legion::Logging)
    end

    def setup_supervision
      Legion::Logging.info 'Setting up Legion::Supervision'
      require 'legion/supervision'
      @supervision = Legion::Supervision.setup
      Legion::Logging.info 'Legion::Supervision started'
    end

    def shutdown_api
      return unless @api_thread

      Legion::API.quit! if defined?(Legion::API) && Legion::API.running?
      @api_thread.kill
      @api_thread = nil
      Legion::Readiness.mark_not_ready(:api)
    rescue StandardError => e
      Legion::Logging.warn "API shutdown error: #{e.message}"
    end

    def shutdown
      Legion::Logging.info('Legion::Service.shutdown was called')
      @shutdown = true
      Legion::Settings[:client][:shutting_down] = true
      Legion::Events.emit('service.shutting_down')

      shutdown_api

      Legion::Metrics.reset! if defined?(Legion::Metrics)

      if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
        Legion::Gaia.shutdown
        Legion::Readiness.mark_not_ready(:gaia)
      end

      Legion::Extensions.shutdown
      Legion::Readiness.mark_not_ready(:extensions)

      if Legion::Settings[:llm]&.dig(:connected)
        Legion::LLM.shutdown
        Legion::Readiness.mark_not_ready(:llm)
      end

      if defined?(Legion::Rbac) && Legion::Settings[:rbac]&.dig(:connected)
        Legion::Rbac.shutdown
        Legion::Readiness.mark_not_ready(:rbac)
      end

      Legion::Data.shutdown if Legion::Settings[:data][:connected]
      Legion::Readiness.mark_not_ready(:data)

      Legion::Leader.reset! if defined?(Legion::Leader)

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

      shutdown_api

      if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
        Legion::Gaia.shutdown
        Legion::Readiness.mark_not_ready(:gaia)
      end

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

      setup_gaia
      Legion::Readiness.mark_ready(:gaia)

      setup_supervision

      load_extensions
      Legion::Readiness.mark_ready(:extensions)

      Legion::Crypt.cs
      setup_api if @api_enabled
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
      Legion::Logging.info 'Legion has been reloaded'
    end

    def load_extensions
      require 'legion/runner'
      Legion::Extensions.hook_extensions
    end

    def self.log_privacy_mode_status
      privacy = if Legion.const_defined?('Settings') && Legion::Settings.respond_to?(:enterprise_privacy?)
                  Legion::Settings.enterprise_privacy?
                else
                  ENV['LEGION_ENTERPRISE_PRIVACY'] == 'true'
                end

      message = if privacy
                  'enterprise_data_privacy enabled: cloud LLM blocked, telemetry suppressed'
                else
                  'enterprise_data_privacy disabled: all tiers available'
                end

      if Legion.const_defined?('Logging')
        Legion::Logging.info(message)
      else
        $stdout.puts "[Legion] #{message}"
      end
    rescue StandardError
      nil
    end
  end
end
