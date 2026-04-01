# frozen_string_literal: true

require 'timeout'
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
      setup_compliance
      setup_local_mode
      reconfigure_logging(log_level)
      Legion::Logging.info("node name: #{Legion::Settings[:client][:name]}")

      if crypt
        require 'legion/crypt'
        Legion::Crypt.start
        Legion::Readiness.mark_ready(:crypt)
        setup_mtls_rotation
      end

      Legion::Settings.resolve_secrets!

      if transport
        setup_transport
        Legion::Readiness.mark_ready(:transport)
        setup_logging_transport
      end

      setup_dispatch

      if cache
        begin
          require 'legion/cache'
          Legion::Cache.setup
          Legion::Readiness.mark_ready(:cache)
        rescue StandardError => e
          Legion::Logging.warn "Legion::Cache remote failed: #{e.message}, falling back to Cache::Local"
          begin
            Legion::Cache::Local.setup
            Legion::Logging.info 'Legion::Cache::Local connected (fallback)'
          rescue StandardError => e2
            Legion::Logging.warn "Legion::Cache::Local also failed: #{e2.message}"
          end
          Legion::Readiness.mark_ready(:cache)
        end
      end

      if data
        begin
          setup_data
          Legion::Readiness.mark_ready(:data)
        rescue StandardError => e
          Legion::Logging.warn "Legion::Data remote failed: #{e.message}, falling back to Data::Local"
          begin
            require 'legion/data'
            Legion::Data::Local.setup if defined?(Legion::Data::Local)
            Legion::Logging.info 'Legion::Data::Local connected (fallback)'
          rescue StandardError => e2
            Legion::Logging.warn "Legion::Data::Local also failed: #{e2.message}"
          end
          Legion::Readiness.mark_ready(:data)
        end
      end

      setup_rbac if data
      setup_cluster if data

      if llm
        begin
          setup_llm
          Legion::Readiness.mark_ready(:llm)
        rescue LoadError
          Legion::Logging.info 'Legion::LLM gem is not installed'
        rescue StandardError => e
          Legion::Logging.warn "Legion::LLM failed: #{e.message}"
        end
      end

      begin
        setup_apollo
        Legion::Readiness.mark_ready(:apollo)
      rescue LoadError
        Legion::Logging.info 'Legion::Apollo gem is not installed, starting without Apollo'
      rescue StandardError => e
        Legion::Logging.warn "Legion::Apollo failed to load: #{e.message}"
      end

      if gaia
        begin
          setup_gaia
          Legion::Readiness.mark_ready(:gaia)
        rescue LoadError
          Legion::Logging.info 'Legion::Gaia gem is not installed'
        rescue StandardError => e
          Legion::Logging.warn "Legion::Gaia failed: #{e.message}"
        end
      end

      setup_telemetry
      setup_audit_archiver
      setup_safety_metrics
      setup_supervision if supervision

      if extensions
        load_extensions
        Legion::Readiness.mark_ready(:extensions)
        setup_generated_functions
      end

      Legion::Gaia.registry&.rediscover if gaia && defined?(Legion::Gaia) && Legion::Gaia.started?

      Legion::Extensions::Agentic::Memory::Trace::Helpers::ErrorTracer.setup if defined?(Legion::Extensions::Agentic::Memory::Trace::Helpers::ErrorTracer)

      Legion::Crypt.cs if crypt

      setup_alerts
      setup_metrics
      setup_task_outcome_observer

      api_settings = Legion::Settings[:api] || {}
      @api_enabled = api && api_settings[:enabled]
      setup_api if @api_enabled
      setup_network_watchdog
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
    end

    def setup_local_mode
      if lite_mode?
        Legion::Logging.info 'Starting in lite mode (zero infrastructure)'
        Legion::Settings[:dev] = true
        require 'legion/transport/local'
        require 'legion/crypt/mock_vault' if defined?(Legion::Crypt)
        return
      end

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

    def lite_mode?
      ENV['LEGION_MODE'] == 'lite' ||
        Legion::Settings[:mode].to_s == 'lite'
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

    def setup_cluster
      cluster_settings = Legion::Settings[:cluster]
      return unless cluster_settings.is_a?(Hash) && cluster_settings[:leader_election] == true

      require 'legion/cluster'
      return unless defined?(Legion::Cluster::Leader)

      @cluster_leader = Legion::Cluster::Leader.new
      @cluster_leader.start
      Legion::Logging.info('Cluster leader election started')
    rescue StandardError => e
      Legion::Logging.warn("Cluster leader setup failed: #{e.message}")
    end

    def setup_settings
      require 'legion/settings'
      directories = Legion::Settings::Loader.default_directories
      existing = directories.select { |d| Dir.exist?(d) }
      Legion::Logging.info "Settings search directories: #{directories.inspect}"
      existing.each { |d| Legion::Logging.info "Settings: will load from #{d}" }
      Legion::Settings.load(config_dirs: existing)
      Legion::Readiness.mark_ready(:settings)
      Legion::Logging.info('Legion::Settings Loaded')
      self.class.log_privacy_mode_status
    end

    def setup_compliance
      require 'legion/compliance'
      Legion::Compliance.setup
    rescue LoadError => e
      Legion::Logging.debug "Compliance module not available: #{e.message}"
    rescue StandardError => e
      Legion::Logging.warn "Compliance setup failed: #{e.message}"
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

    def reconfigure_logging(cli_level = nil)
      ls = Legion::Settings[:logging] || {}
      level = cli_level || ls[:level] || 'info'

      Legion::Logging.setup(
        level:       level,
        format:      (ls[:format] || 'text').to_sym,
        log_file:    ls[:log_file],
        log_stdout:  ls.fetch(:log_stdout, true),
        trace:       ls.fetch(:trace, true),
        async:       ls.fetch(:async, true),
        include_pid: ls.fetch(:include_pid, false)
      )
    end

    def setup_api # rubocop:disable Metrics/MethodLength
      if @api_thread&.alive?
        Legion::Logging.warn 'API already running, skipping duplicate setup_api call'
        return
      end

      require 'legion/api'
      api_settings = Legion::Settings[:api]
      port = api_settings[:port]
      bind = api_settings[:bind]

      Legion::API.set :port, port
      Legion::API.set :bind, bind
      Legion::API.set :server, :puma
      Legion::API.set :environment, :production

      puma_cfg    = api_settings[:puma]
      min_threads = puma_cfg[:min_threads]
      max_threads = puma_cfg[:max_threads]
      thread_spec = "#{min_threads}:#{max_threads}"
      puma_timeouts = {
        persistent_timeout: puma_cfg[:persistent_timeout],
        first_data_timeout: puma_cfg[:first_data_timeout]
      }.compact

      tls_cfg = build_api_tls_config(api_settings)
      if tls_cfg
        Legion::API.set :ssl_bind_options, tls_cfg
        Legion::API.set :server_settings, { quiet: true, Threads: thread_spec, **puma_timeouts,
                                            **ssl_server_settings(tls_cfg, bind, port) }
        Legion::Logging.info "Starting Legion API (TLS) on #{bind}:#{port}"
      else
        require 'puma'
        puma_log = ::Puma::LogWriter.new(StringIO.new, StringIO.new)
        Legion::API.set :server_settings, { log_writer: puma_log, quiet: true, Threads: thread_spec, **puma_timeouts }
        Legion::Logging.info "Starting Legion API on #{bind}:#{port}"
      end

      @api_thread = Thread.new do
        retries = 0
        max_retries = api_settings[:bind_retries]
        retry_wait  = api_settings[:bind_retry_wait]

        begin
          raise Errno::EADDRINUSE, "port #{port} already bound" if port_in_use?(bind, port)

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
        ensure
          Legion::Process.quit_flag&.make_true if !@shutdown && defined?(Legion::Process)
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

    def setup_apollo
      Legion::Logging.info 'Setting up Legion::Apollo'
      require 'legion/apollo'
      Legion::Apollo.start
      Legion::Apollo::Local.start if defined?(Legion::Apollo::Local)
      Legion::Logging.info 'Legion::Apollo started'
    rescue LoadError
      Legion::Logging.info 'Legion::Apollo gem is not installed, starting without Apollo'
    rescue StandardError => e
      Legion::Logging.warn "Legion::Apollo failed to load: #{e.message}"
    end

    def setup_dispatch
      require 'legion/dispatch'
      Legion::Dispatch.dispatcher.start
      Legion::Logging.info "[Service] Dispatch started (strategy: #{Legion::Dispatch.dispatcher.class.name})"
    end

    def setup_transport
      Legion::Logging.info 'Setting up Legion::Transport'
      require 'legion/transport'
      Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
      Legion::Transport::Connection.setup
      Legion::Logging.info 'Legion::Transport connected'
    end

    def setup_logging_transport # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return unless defined?(Legion::Transport::Connection)
      return unless Legion::Transport::Connection.session_open?

      lt_settings = begin
        Legion::Settings.dig(:logging, :transport) || {}
      rescue StandardError
        {}
      end
      return unless lt_settings[:enabled] == true

      forward_logs       = lt_settings.fetch(:forward_logs, true)
      forward_exceptions = lt_settings.fetch(:forward_exceptions, true)
      return unless forward_logs || forward_exceptions

      log_session = Legion::Transport::Connection.create_dedicated_session(name: 'legion-logging')
      @log_session = log_session
      log_channel = log_session.create_channel
      log_channel.prefetch(1)
      exchange = log_channel.topic('legion.logging', durable: true)

      if forward_logs
        Legion::Logging.log_writer = lambda { |event, routing_key:|
          begin
            next unless log_channel&.open?

            exchange.publish(Legion::JSON.dump(event), routing_key: routing_key)
          rescue StandardError
            nil
          end
        }
      end

      if forward_exceptions
        Legion::Logging.exception_writer = lambda { |event, routing_key:, headers:, properties:|
          begin
            next unless log_channel&.open?

            exchange.publish(
              Legion::JSON.dump(event),
              routing_key: routing_key,
              headers:     headers,
              **properties
            )
          rescue StandardError
            nil
          end
        }
      end

      modes = []
      modes << 'logs' if forward_logs
      modes << 'exceptions' if forward_exceptions
      Legion::Logging.info("Logging transport wired: #{modes.join(' + ')} (dedicated session)")
    rescue StandardError => e
      Legion::Logging.warn "Logging transport setup failed: #{e.message}"
      teardown_logging_transport
    end

    def teardown_logging_transport
      Legion::Logging.log_writer = nil
      Legion::Logging.exception_writer = nil
      @log_session&.close if @log_session.respond_to?(:close) &&
                             (!@log_session.respond_to?(:open?) || @log_session.open?)
      @log_session = nil
    rescue StandardError
      nil
    end

    def setup_alerts
      enabled = begin
        Legion::Settings[:alerts][:enabled]
      rescue StandardError => e
        Legion::Logging.debug "Service#setup_alerts failed to read alerts.enabled: #{e.message}" if defined?(Legion::Logging)
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

    def setup_task_outcome_observer
      require_relative 'task_outcome_observer'
      return unless Legion::TaskOutcomeObserver.enabled?

      Legion::TaskOutcomeObserver.setup
    rescue StandardError => e
      Legion::Logging.warn "TaskOutcomeObserver setup failed: #{e.message}"
    end

    def setup_telemetry
      return unless begin
        Legion::Settings.dig(:telemetry, :enabled)
      rescue StandardError => e
        Legion::Logging.debug "Service#setup_telemetry failed to read telemetry.enabled: #{e.message}" if defined?(Legion::Logging)
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

    def setup_audit_archiver
      require_relative 'audit/archiver_actor'
      return unless Legion::Audit::ArchiverActor.enabled?

      @audit_archiver_thread = Thread.new do
        loop do
          Legion::Audit::ArchiverActor.new.run_archival
        rescue StandardError => e
          Legion::Logging.error "[Audit::ArchiverActor] error: #{e.message}" if defined?(Legion::Logging)
        ensure
          sleep Legion::Audit::ArchiverActor::INTERVAL_SECONDS
        end
      end
      @audit_archiver_thread.abort_on_exception = false
      Legion::Logging.info 'Audit archiver actor started' if defined?(Legion::Logging)
    rescue StandardError => e
      Legion::Logging.warn "Audit archiver setup failed: #{e.message}" if defined?(Legion::Logging)
    end

    def shutdown_audit_archiver
      @audit_archiver_thread&.kill
      @audit_archiver_thread = nil
    end

    def setup_safety_metrics
      require_relative 'telemetry/safety_metrics'
      Legion::Telemetry::SafetyMetrics.start
    rescue LoadError => e
      Legion::Logging.debug "Service#setup_safety_metrics: safety_metrics not available: #{e.message}" if defined?(Legion::Logging)
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

      shutdown_network_watchdog
      shutdown_audit_archiver
      shutdown_api

      Legion::Metrics.reset! if defined?(Legion::Metrics)

      if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
        shutdown_component('Gaia') { Legion::Gaia.shutdown }
        Legion::Readiness.mark_not_ready(:gaia)
      end

      if @cluster_leader
        @cluster_leader.stop
        @cluster_leader = nil
      end

      shutdown_component('Dispatch') { Legion::Dispatch.shutdown } if defined?(Legion::Dispatch)

      ext_timeout = Legion::Settings.dig(:extensions, :shutdown_timeout) || 15
      shutdown_component('Extensions', timeout: ext_timeout) { Legion::Extensions.shutdown }
      Legion::Readiness.mark_not_ready(:extensions)

      if Legion::Settings[:llm]&.dig(:connected)
        shutdown_component('LLM') { Legion::LLM.shutdown }
        Legion::Readiness.mark_not_ready(:llm)
      end

      if defined?(Legion::Rbac) && Legion::Settings[:rbac]&.dig(:connected)
        shutdown_component('Rbac') { Legion::Rbac.shutdown }
        Legion::Readiness.mark_not_ready(:rbac)
      end

      shutdown_component('Data') { Legion::Data.shutdown } if Legion::Settings[:data][:connected]
      Legion::Readiness.mark_not_ready(:data)

      Legion::Leader.reset! if defined?(Legion::Leader)

      shutdown_component('Cache') { Legion::Cache.shutdown }
      Legion::Readiness.mark_not_ready(:cache)

      teardown_logging_transport
      shutdown_component('Transport') { Legion::Transport::Connection.shutdown }
      Legion::Readiness.mark_not_ready(:transport)

      shutdown_mtls_rotation
      shutdown_component('Crypt') { Legion::Crypt.shutdown }
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Settings[:client][:ready] = false
      Legion::Events.emit('service.shutdown')
    end

    def reload # rubocop:disable Metrics/MethodLength
      return if @reloading

      @reloading = true
      Legion::Logging.info 'Legion::Service.reload was called'
      Legion::Settings[:client][:ready] = false

      shutdown_network_watchdog
      shutdown_api

      if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
        shutdown_component('Gaia') { Legion::Gaia.shutdown }
        Legion::Readiness.mark_not_ready(:gaia)
      end

      ext_timeout = Legion::Settings.dig(:extensions, :shutdown_timeout) || 15
      shutdown_component('Extensions', timeout: ext_timeout) { Legion::Extensions.shutdown }
      Legion::Readiness.mark_not_ready(:extensions)

      shutdown_component('Data') { Legion::Data.shutdown }
      Legion::Readiness.mark_not_ready(:data)

      shutdown_component('Cache') { Legion::Cache.shutdown }
      Legion::Readiness.mark_not_ready(:cache)

      teardown_logging_transport
      shutdown_component('Transport') { Legion::Transport::Connection.shutdown }
      Legion::Readiness.mark_not_ready(:transport)

      shutdown_component('Crypt') { Legion::Crypt.shutdown }
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Readiness.wait_until_not_ready(:transport, :data, :cache, :crypt)

      Legion::Settings.load(force: true, config_dirs: Legion::Settings::Loader.default_directories.select { |d| Dir.exist?(d) })
      Legion::Readiness.mark_ready(:settings)

      Legion::Crypt.start if defined?(Legion::Crypt)
      Legion::Readiness.mark_ready(:crypt)

      setup_transport
      Legion::Readiness.mark_ready(:transport)
      teardown_logging_transport
      setup_logging_transport

      require 'legion/cache' unless defined?(Legion::Cache)
      Legion::Cache.setup
      Legion::Readiness.mark_ready(:cache)

      setup_data
      Legion::Readiness.mark_ready(:data)

      setup_rbac if defined?(Legion::Rbac)
      setup_llm if defined?(Legion::LLM)

      setup_gaia if defined?(Legion::Gaia)
      Legion::Readiness.mark_ready(:gaia)

      setup_supervision
      load_extensions
      Legion::Readiness.mark_ready(:extensions)

      Legion::Crypt.cs
      setup_api if @api_enabled
      setup_network_watchdog
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
      Legion::Logging.info 'Legion has been reloaded'
    ensure
      @reloading = false
    end

    def load_extensions
      require 'legion/runner'
      Legion::Extensions.hook_extensions
    end

    def setup_generated_functions
      return unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)

      loaded = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.load_on_boot
      Legion::Logging.info("Loaded #{loaded} generated functions") if defined?(Legion::Logging) && loaded.to_i.positive?
    rescue StandardError => e
      Legion::Logging.warn("setup_generated_functions failed: #{e.message}") if defined?(Legion::Logging)
    end

    def setup_mtls_rotation
      enabled = Legion::Settings[:security]&.dig(:mtls, :enabled)
      return unless enabled

      unless defined?(Legion::Crypt::CertRotation)
        require 'legion/crypt/mtls'
        require 'legion/crypt/cert_rotation'
      end
      return unless defined?(Legion::Crypt::CertRotation)

      @cert_rotation = Legion::Crypt::CertRotation.new
      @cert_rotation.start
      Legion::Logging.info '[mTLS] CertRotation started'
    rescue LoadError => e
      Legion::Logging.warn "mTLS rotation skipped: #{e.message}"
    rescue StandardError => e
      Legion::Logging.warn "mTLS rotation setup failed: #{e.message}"
    end

    def shutdown_mtls_rotation
      return unless @cert_rotation

      @cert_rotation.stop
      @cert_rotation = nil
    rescue StandardError => e
      Legion::Logging.warn "mTLS rotation shutdown error: #{e.message}"
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
    rescue StandardError => e
      Legion::Logging.debug "Service#log_privacy_mode_status failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    def shutdown_component(name, timeout: 5, &)
      Timeout.timeout(timeout, &)
    rescue Timeout::Error
      Legion::Logging.warn "#{name} shutdown timed out after #{timeout}s, forcing"
    rescue StandardError => e
      Legion::Logging.warn "#{name} shutdown error: #{e.class}: #{e.message}"
    end

    def setup_network_watchdog
      return unless Legion::Settings.dig(:network, :watchdog, :enabled)

      @consecutive_failures = Concurrent::AtomicFixnum.new(0)
      threshold = Legion::Settings.dig(:network, :watchdog, :failure_threshold) || 5
      interval = Legion::Settings.dig(:network, :watchdog, :check_interval) || 15

      @network_watchdog = Concurrent::TimerTask.new(execution_interval: interval) do
        if network_healthy?
          prev = @consecutive_failures.value
          @consecutive_failures.value = 0
          if prev >= threshold
            Legion::Logging.info '[Watchdog] Network restored, triggering reload'
            Thread.new { Legion.reload } unless @reloading
          end
        else
          count = @consecutive_failures.increment
          Legion::Logging.warn "[Watchdog] Network check failed (#{count}/#{threshold})"
          if count == threshold
            Legion::Logging.error '[Watchdog] Network failure threshold reached, pausing actors'
            Legion::Extensions.pause_actors if Legion::Extensions.respond_to?(:pause_actors)
          end
        end
      rescue StandardError => e
        Legion::Logging.debug "[Watchdog] check error: #{e.message}"
      end
      @network_watchdog.execute
      Legion::Logging.info "[Watchdog] Network watchdog started (interval=#{interval}s, threshold=#{threshold})"
    rescue StandardError => e
      Legion::Logging.warn "Network watchdog setup failed: #{e.message}"
    end

    def shutdown_network_watchdog
      @network_watchdog&.shutdown
      @network_watchdog = nil
    end

    def network_healthy?
      return true if defined?(Legion::Transport::Connection) && Legion::Transport::Connection.lite_mode?

      checks = []
      checks << Legion::Transport::Connection.session_open? if Legion::Settings[:transport][:connected]
      if Legion::Settings[:data][:connected] && defined?(Legion::Data::Connection)
        checks << (Legion::Data::Connection.sequel&.test_connection rescue false) # rubocop:disable Style/RescueModifier
      end
      checks << Legion::Cache.connected? if Legion::Settings[:cache][:connected] && defined?(Legion::Cache)
      return true if checks.empty?

      checks.any?
    rescue StandardError
      false
    end

    private

    def port_in_use?(bind, port)
      TCPServer.new(bind, port).close
      false
    rescue Errno::EADDRINUSE
      true
    end

    def build_api_tls_config(api_settings)
      tls = api_settings[:tls] || {}
      tls = tls.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      return nil unless tls[:enabled] == true

      cert = tls[:cert]
      key  = tls[:key]

      unless cert && !cert.to_s.empty? && key && !key.to_s.empty?
        Legion::Logging.warn 'api.tls enabled but cert or key is missing — falling back to plain HTTP'
        return nil
      end

      {
        cert:        cert,
        key:         key,
        ca:          tls[:ca],
        verify_mode: verify_mode_for(tls[:verify])
      }.compact
    end

    def ssl_server_settings(tls_cfg, bind, port)
      return {} unless tls_cfg

      { binds: ["ssl://#{bind}:#{port}?cert=#{tls_cfg[:cert]}&key=#{tls_cfg[:key]}"] }
    end

    def verify_mode_for(verify)
      case verify.to_s
      when 'none'   then 'none'
      when 'mutual' then 'force_peer'
      else               'peer'
      end
    end
  end
end
