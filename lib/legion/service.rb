# frozen_string_literal: true

require 'timeout'
require 'legion/logging'
require_relative 'readiness'
require_relative 'mode'
require_relative 'process_role'

module Legion
  class Service
    include Legion::Logging::Helper

    class << self
      include Legion::Logging::Helper

      private

      def resolve_logger_settings
        raw_logging = (Legion::Settings[:logging] if defined?(Legion::Settings) && Legion::Settings.respond_to?(:[]))
        raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
      end
    end

    def modules
      base = [Legion::Crypt, Legion::Transport, Legion::Cache, Legion::Data, Legion::Supervision]
      base << Legion::LLM if defined?(Legion::LLM)
      base << Legion::Gaia if defined?(Legion::Gaia)
      base.freeze
    end

    def initialize(transport: nil, cache: nil, data: nil, supervision: nil, extensions: nil, # rubocop:disable Metrics/CyclomaticComplexity,Metrics/ParameterLists,Metrics/MethodLength,Metrics/PerceivedComplexity,Metrics/AbcSize
                   crypt: nil, api: nil, llm: nil, gaia: nil, log_level: nil, http_port: nil,
                   role: nil)
      role_opts = Legion::ProcessRole.resolve(role || Legion::ProcessRole.current)
      transport = role_opts[:transport] if transport.nil?
      cache = role_opts[:cache] if cache.nil?
      data = role_opts[:data] if data.nil?
      supervision = role_opts[:supervision] if supervision.nil?
      extensions = role_opts[:extensions] if extensions.nil?
      crypt = role_opts[:crypt] if crypt.nil?
      api = role_opts[:api] if api.nil?
      llm = role_opts[:llm] if llm.nil?
      gaia = role_opts[:gaia] if gaia.nil?

      setup_logging(log_level: bootstrap_log_level(log_level))
      log.debug('Starting Legion::Service')
      setup_settings
      apply_cli_overrides(http_port: http_port)
      setup_compliance
      setup_local_mode
      reconfigure_logging(log_level)
      log.info("node name: #{Legion::Settings[:client][:name]}")

      if crypt
        require 'legion/crypt'
        Legion::Crypt.start
        Legion::Readiness.mark_ready(:crypt)
        setup_mtls_rotation
        # Phase 5: fetch short-lived bootstrap RMQ creds from Vault before transport connects.
        # Service is the authoritative gate (vault_connected? + dynamic_rmq_creds?).
        fetch_phase5_bootstrap_creds unless Legion::Mode.respond_to?(:lite?) && Legion::Mode.lite?
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
          handle_exception(e, level: :warn, operation: 'service.initialize.cache', fallback: 'cache_local')
          begin
            Legion::Cache::Local.setup
            log.info 'Legion::Cache::Local connected (fallback)'
          rescue StandardError => e2
            handle_exception(e2, level: :warn, operation: 'service.initialize.cache_local')
          end
          Legion::Readiness.mark_ready(:cache)
        end
      end

      if data
        begin
          setup_data
          Legion::Readiness.mark_ready(:data)
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'service.initialize.data', fallback: 'data_local')
          begin
            require 'legion/data'
            Legion::Data::Local.setup if defined?(Legion::Data::Local)
            log.info 'Legion::Data::Local connected (fallback)'
          rescue StandardError => e2
            handle_exception(e2, level: :warn, operation: 'service.initialize.data_local')
          end
          Legion::Readiness.mark_ready(:data)
        end
      end

      if data
        setup_rbac
      else
        Legion::Readiness.mark_skipped(:rbac)
      end
      setup_cluster if data

      if llm
        begin
          setup_llm
          Legion::Readiness.mark_ready(:llm)
        rescue LoadError => e
          handle_exception(e, level: :debug, operation: 'service.initialize.llm', availability: 'missing')
          log.info 'Legion::LLM gem is not installed'
          Legion::Readiness.mark_skipped(:llm)
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'service.initialize.llm')
          Legion::Readiness.mark_skipped(:llm)
        end
      else
        Legion::Readiness.mark_skipped(:llm)
      end

      begin
        setup_apollo
        Legion::Readiness.mark_ready(:apollo)
      rescue LoadError => e
        handle_exception(e, level: :debug, operation: 'service.initialize.apollo', availability: 'missing')
        log.info 'Legion::Apollo gem is not installed, starting without Apollo'
        Legion::Readiness.mark_skipped(:apollo)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'service.initialize.apollo')
        Legion::Readiness.mark_skipped(:apollo)
      end

      if gaia
        begin
          setup_gaia
          Legion::Readiness.mark_ready(:gaia)
        rescue LoadError => e
          handle_exception(e, level: :debug, operation: 'service.initialize.gaia', availability: 'missing')
          log.info 'Legion::Gaia gem is not installed'
          Legion::Readiness.mark_skipped(:gaia)
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'service.initialize.gaia')
          Legion::Readiness.mark_skipped(:gaia)
        end
      else
        Legion::Readiness.mark_skipped(:gaia)
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

      # Identity resolution — after extensions so lex-identity-* providers are loaded
      setup_identity if transport

      register_core_tools

      Legion::Gaia.registry&.rediscover if gaia && defined?(Legion::Gaia) && Legion::Gaia.started?

      Legion::Extensions::Agentic::Memory::Trace::Helpers::ErrorTracer.setup if defined?(Legion::Extensions::Agentic::Memory::Trace::Helpers::ErrorTracer)

      Legion::Crypt.cs if crypt

      setup_alerts
      setup_metrics
      setup_task_outcome_observer

      # Pre-warm MCP server in background; async embedding build
      Thread.new do
        require 'legion/mcp' if defined?(Legion::Settings) && !defined?(Legion::MCP)
        Legion::MCP.server if defined?(Legion::MCP) && Legion::MCP.respond_to?(:server)
        Legion::MCP::Server.populate_embedding_index if defined?(Legion::MCP::Server) && Legion::MCP::Server.respond_to?(:populate_embedding_index)
      rescue StandardError => e
        log.warn("MCP pre-warm failed: #{e.message}")
      end

      require 'sinatra/base'
      require 'legion/api/default_settings'
      api_settings = Legion::Settings[:api]
      @api_enabled = api && api_settings[:enabled]
      setup_apm if @api_enabled
      setup_api if @api_enabled
      setup_network_watchdog
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
    end

    def setup_local_mode
      if lite_mode?
        log.info 'Starting in lite mode (zero infrastructure)'
        Legion::Settings[:dev] = true
        require 'legion/transport/local'
        require 'legion/crypt/mock_vault' if defined?(Legion::Crypt)
        return
      end

      return unless local_mode?

      log.info 'Starting in local development mode'
      Legion::Settings[:dev] = true

      require 'legion/transport/local'
      require 'legion/crypt/mock_vault'
    end

    def local_mode?
      ENV['LEGION_LOCAL'] == 'true' ||
        Legion::Settings[:local_mode] == true
    end

    def lite_mode?
      Legion::Mode.lite?
    end

    def setup_data
      log.info 'Setting up Legion::Data'
      require 'legion/data'
      Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
      Legion::Data.setup
      log.info 'Legion::Data connected'
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_data', availability: 'missing')
      log.info 'Legion::Data gem is not installed, please install it manually with gem install legion-data'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_data')
    end

    def setup_rbac
      require 'legion/rbac'
      Legion::Rbac.setup
      Legion::Readiness.mark_ready(:rbac)
      log.info 'Legion::Rbac loaded'
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_rbac', availability: 'missing')
      log.debug 'Legion::Rbac gem is not installed, starting without RBAC'
      Legion::Readiness.mark_skipped(:rbac)
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_rbac')
      Legion::Readiness.mark_skipped(:rbac)
    end

    def setup_cluster
      cluster_settings = Legion::Settings[:cluster]
      return unless cluster_settings.is_a?(Hash) && cluster_settings[:leader_election] == true

      require 'legion/cluster'
      return unless defined?(Legion::Cluster::Leader)

      @cluster_leader = Legion::Cluster::Leader.new
      @cluster_leader.start
      log.info('Cluster leader election started')
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_cluster')
    end

    def setup_settings
      require 'legion/settings'
      directories = Legion::Settings::Loader.default_directories
      existing = directories.select { |d| Dir.exist?(d) }
      log.info "Settings search directories: #{directories.inspect}"
      existing.each { |d| log.info "Settings: will load from #{d}" }
      if Legion::Settings.respond_to?(:loaded?) && Legion::Settings.loaded?
        log.info 'Legion::Settings already loaded, skipping reload'
      else
        Legion::Settings.load(config_dirs: existing)
      end
      Legion::Readiness.mark_ready(:settings)
      log.info('Legion::Settings Loaded')
      self.class.log_privacy_mode_status
    end

    def setup_compliance
      require 'legion/compliance'
      Legion::Compliance.setup
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_compliance', availability: 'missing')
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_compliance')
    end

    def apply_cli_overrides(http_port: nil)
      return unless http_port

      Legion::Settings[:api] ||= {}
      Legion::Settings[:api][:port] = http_port
      log.info "CLI override: API port set to #{http_port}"
    end

    def setup_logging(log_level: 'info', **_opts)
      require 'legion/logging'
      Legion::Logging.setup(log_level: log_level, level: log_level, trace: true)
    end

    def reconfigure_logging(cli_level = nil)
      ls = Legion::Settings[:logging] || {}
      level = if cli_level.respond_to?(:empty?) && cli_level.empty?
                nil
              else
                cli_level
              end
      level ||= ls[:level] || 'info'

      Legion::Logging.setup(
        level:       level,
        format:      (ls[:format] || 'text').to_sym,
        log_file:    ls[:log_file],
        log_stdout:  ls.fetch(:log_stdout, true),
        trace:       ls.fetch(:trace, true),
        async:       ls.fetch(:async, true),
        include_pid: ls.fetch(:include_pid, false),
        color:       true
      )
    end

    def setup_apm
      apm_settings = Legion::Settings.dig(:api, :elastic_apm) || {}
      return unless apm_settings[:enabled]

      require 'elastic-apm'

      config = build_apm_config(apm_settings)
      ElasticAPM.start(**config)
      @apm_running = true
      log.info "Elastic APM started: server=#{config[:server_url]} service=#{config[:service_name]}"
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_apm', availability: 'missing')
      log.info 'elastic-apm gem is not installed, starting without APM'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_apm')
    end

    def shutdown_apm
      return unless @apm_running

      ElasticAPM.stop if defined?(ElasticAPM) && ElasticAPM.running?
      @apm_running = false
      log.info 'Elastic APM stopped'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.shutdown_apm')
    end

    def setup_api # rubocop:disable Metrics/MethodLength
      if @api_thread&.alive?
        log.warn 'API already running, skipping duplicate setup_api call'
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

      puma_cfg = api_settings[:puma]
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
        log.info "Starting Legion API (TLS) on #{bind}:#{port}"
      else
        require 'puma'
        puma_log = ::Puma::LogWriter.new(StringIO.new, StringIO.new)
        Legion::API.set :server_settings, { log_writer: puma_log, quiet: true, Threads: thread_spec, **puma_timeouts }
        log.info "Starting Legion API on #{bind}:#{port}"
      end

      # Mount identity middleware — bridges legion.auth to legion.principal
      if defined?(Legion::Identity::Middleware)
        require_auth = Legion::Identity::Middleware.require_auth?(bind: bind, mode: Legion::Mode.current)
        Legion::API.use Legion::Identity::Middleware, require_auth: require_auth
      end

      @api_thread = Thread.new do
        retries = 0
        max_retries = api_settings[:bind_retries]
        retry_wait = api_settings[:bind_retry_wait]

        begin
          raise Errno::EADDRINUSE, "port #{port} already bound" if port_in_use?(bind, port)

          Legion::API.run!(traps: false)
        rescue Errno::EADDRINUSE
          retries += 1
          if retries <= max_retries
            log.warn "Port #{port} in use, retrying in #{retry_wait}s (attempt #{retries}/#{max_retries})"
            sleep retry_wait
            retry
          else
            log.error "Port #{port} still in use after #{max_retries} attempts, API disabled"
            Legion::Readiness.mark_not_ready(:api)
          end
        ensure
          Legion::Process.quit_flag&.make_true if !@shutdown && defined?(Legion::Process)
        end
      end
      Legion::Readiness.mark_ready(:api)
    rescue LoadError => e
      handle_exception(e, level: :warn, operation: 'service.setup_api', dependency: 'api')
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_api')
    end

    def setup_llm
      log.info 'Setting up Legion::LLM'
      require 'legion/llm'
      Legion::Settings.merge_settings('llm', Legion::LLM::Settings.default)
      Legion::LLM.start
      log.info 'Legion::LLM started'
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_llm', availability: 'missing')
      log.info 'Legion::LLM gem is not installed, starting without LLM support'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_llm')
    end

    def setup_gaia
      log.info 'Setting up Legion::Gaia'
      require 'legion/gaia'
      Legion::Settings.merge_settings('gaia', Legion::Gaia::Settings.default)
      Legion::Gaia.boot
      log.info 'Legion::Gaia booted'
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_gaia', availability: 'missing')
      log.info 'Legion::Gaia gem is not installed, starting without cognitive layer'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_gaia')
    end

    def setup_apollo
      log.info 'Setting up Legion::Apollo'
      require 'legion/apollo'
      Legion::Apollo.start
      Legion::Apollo::Local.start if defined?(Legion::Apollo::Local)
      log.info 'Legion::Apollo started'
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_apollo', availability: 'missing')
      log.info 'Legion::Apollo gem is not installed, starting without Apollo'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_apollo')
    end

    def setup_dispatch
      require 'legion/dispatch'
      Legion::Dispatch.dispatcher.start
      log.info "[Service] Dispatch started (strategy: #{Legion::Dispatch.dispatcher.class.name})"
    end

    def setup_transport
      log.info 'Setting up Legion::Transport'
      require 'legion/transport'
      Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
      Legion::Transport::Connection.setup
      log.info 'Legion::Transport connected'
    end

    def setup_identity # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      require_relative 'identity/process'
      require_relative 'identity/broker'
      require_relative 'identity/lease'
      require_relative 'identity/lease_renewer'
      require_relative 'identity/request'
      require_relative 'identity/middleware'

      # Resolve identity from available providers (Phase 4 adds real providers)
      resolved = resolve_identity_providers
      unless resolved
        Legion::Identity::Process.bind_fallback!
        log.info "[Identity] fallback identity: #{Legion::Identity::Process.canonical_name}"
      end

      # Phase 5: Swap from bootstrap RMQ credentials to identity-scoped credentials.
      # Gate on vault_connected? + dynamic_rmq_creds? — NOT on resolved? (fallback identity
      # still needs scoped creds via the mode-based role).
      if defined?(Legion::Crypt) &&
         Legion::Crypt.respond_to?(:vault_connected?) && Legion::Crypt.vault_connected? &&
         Legion::Crypt.respond_to?(:dynamic_rmq_creds?) && Legion::Crypt.dynamic_rmq_creds? &&
         Legion::Crypt.respond_to?(:swap_to_identity_creds) &&
         !Legion::Mode.lite?
        log.info '[Identity] swapping to identity-scoped RMQ credentials'
        Legion::Crypt.swap_to_identity_creds(mode: Legion::Mode.current)
      end

      # Re-resolve secrets for any identity-scoped lease:// refs (task 2.25)
      Legion::Settings.resolve_secrets! if Legion::Settings.respond_to?(:resolve_secrets!)

      # Fire-and-forget JWKS prefetch
      jwks_url = Legion::Settings.dig(:identity, :jwks_endpoint) || Legion::Settings.dig(:crypt, :jwt, :jwks_endpoint)
      if jwks_url && defined?(Legion::Crypt::JwksClient)
        Legion::Crypt::JwksClient.prefetch!(jwks_url)
        Legion::Crypt::JwksClient.start_background_refresh!(jwks_url)
      end

      log.info "[Identity] resolved=#{Legion::Identity::Process.resolved?} mode=#{Legion::Mode.current} queue_prefix=#{Legion::Identity::Process.queue_prefix}"
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_identity')
      Legion::Identity::Process.bind_fallback! if defined?(Legion::Identity::Process) && !Legion::Identity::Process.resolved?
    ensure
      Legion::Readiness.mark_ready(:identity)
      begin
        Legion::Extensions.flush_pending_registrations! if defined?(Legion::Extensions) &&
                                                           Legion::Extensions.respond_to?(:flush_pending_registrations!)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'service.setup_identity.flush_pending_registrations')
      end
    end

    def setup_logging_transport # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      return unless defined?(Legion::Transport::Connection)
      return unless Legion::Transport::Connection.session_open?

      lt_settings = begin
        Legion::Settings.dig(:logging, :transport) || {}
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'service.setup_logging_transport.read_settings')
        {}
      end
      return unless lt_settings[:enabled] == true

      forward_logs = lt_settings.fetch(:forward_logs, true)
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
      log.info("Logging transport wired: #{modes.join(' + ')} (dedicated session)")
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_logging_transport')
      teardown_logging_transport
    end

    def teardown_logging_transport
      Legion::Logging.log_writer = nil
      Legion::Logging.exception_writer = nil
      @log_session&.close if @log_session.respond_to?(:close) &&
                             (!@log_session.respond_to?(:open?) || @log_session.open?)
      @log_session = nil
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'service.teardown_logging_transport')
      nil
    end

    def setup_alerts
      alerts_settings = Legion::Settings[:alerts]
      enabled = alerts_settings.is_a?(Hash) ? alerts_settings[:enabled] : false
      return unless enabled

      require 'legion/alerts'
      Legion::Alerts.setup
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_alerts')
    end

    def setup_metrics
      require 'legion/metrics'
      Legion::Metrics.setup
      log.debug 'Legion::Metrics initialized'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_metrics')
    end

    def setup_task_outcome_observer
      require_relative 'task_outcome_observer'
      return unless Legion::TaskOutcomeObserver.enabled?

      Legion::TaskOutcomeObserver.setup
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_task_outcome_observer')
    end

    def setup_telemetry
      return unless begin
        Legion::Settings.dig(:telemetry, :enabled)
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'service.setup_telemetry.read_enabled')
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

      log.info "OpenTelemetry initialized: endpoint=#{endpoint} service=#{service_name}"
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_telemetry', availability: 'missing')
      log.info 'OpenTelemetry gems not installed, starting without telemetry'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_telemetry', endpoint: endpoint, service_name: service_name)
    end

    def setup_audit_archiver
      require_relative 'audit/archiver_actor'
      return unless Legion::Audit::ArchiverActor.enabled?

      @audit_archiver_thread = Thread.new do
        loop do
          Legion::Audit::ArchiverActor.new.run_archival
        rescue StandardError => e
          handle_exception(e, level: :error, operation: 'service.audit_archiver.run')
        ensure
          sleep Legion::Audit::ArchiverActor::INTERVAL_SECONDS
        end
      end
      @audit_archiver_thread.abort_on_exception = false
      log.info 'Audit archiver actor started'
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_audit_archiver')
    end

    def shutdown_audit_archiver
      @audit_archiver_thread&.kill
      @audit_archiver_thread = nil
    end

    def setup_safety_metrics
      require_relative 'telemetry/safety_metrics'
      Legion::Telemetry::SafetyMetrics.start
    rescue LoadError => e
      handle_exception(e, level: :debug, operation: 'service.setup_safety_metrics', availability: 'missing')
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'service.setup_safety_metrics')
    end

    def setup_supervision
      log.info 'Setting up Legion::Supervision'
      require 'legion/supervision'
      @supervision = Legion::Supervision.setup
      log.info 'Legion::Supervision started'
    end

    def shutdown_api
      return unless @api_thread

      Legion::API.quit! if defined?(Legion::API) && Legion::API.running?
      @api_thread.kill
      @api_thread = nil
      Legion::Readiness.mark_not_ready(:api)
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.shutdown_api')
    end

    def shutdown # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/MethodLength
      log.info('Legion::Service.shutdown was called')
      @shutdown = true
      Legion::Settings[:client][:shutting_down] = true
      Legion::Events.emit('service.shutting_down')

      shutdown_network_watchdog
      shutdown_audit_archiver
      shutdown_api
      shutdown_apm

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

      Legion::Tools::Registry.clear if defined?(Legion::Tools::Registry)

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

      # Identity: cooperative shutdown of Broker (stops all LeaseRenewer threads)
      if defined?(Legion::Identity::Broker)
        shutdown_component('Identity::Broker') { Legion::Identity::Broker.shutdown }
        Legion::Readiness.mark_not_ready(:identity)
      end

      # Stop JWKS background refresh
      if defined?(Legion::Crypt::JwksClient) && Legion::Crypt::JwksClient.respond_to?(:stop_background_refresh!)
        Legion::Crypt::JwksClient.stop_background_refresh!
      end

      teardown_logging_transport
      shutdown_component('Transport') { Legion::Transport::Connection.shutdown }
      Legion::Readiness.mark_not_ready(:transport)

      shutdown_mtls_rotation
      # Phase 5: Revoke bootstrap RMQ lease on clean shutdown (defense-in-depth;
      # lease expires naturally if process crashes before identity swap).
      Legion::Crypt.revoke_bootstrap_lease if defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:revoke_bootstrap_lease)
      shutdown_component('Crypt') { Legion::Crypt.shutdown if defined?(Legion::Crypt) }
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Settings[:client][:ready] = false
      Legion::Events.emit('service.shutdown')
    end

    def reload # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      return if @reloading

      @reloading = true
      log.info 'Legion::Service.reload was called'
      Legion::Settings[:client][:ready] = false

      shutdown_network_watchdog
      shutdown_api
      shutdown_apm

      if defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?
        shutdown_component('Gaia') { Legion::Gaia.shutdown }
        Legion::Readiness.mark_not_ready(:gaia)
      end

      Legion::Tools::Registry.clear if defined?(Legion::Tools::Registry)
      Legion::Tools::EmbeddingCache.clear_memory if defined?(Legion::Tools::EmbeddingCache) && Legion::Tools::EmbeddingCache.respond_to?(:clear_memory)

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

      shutdown_component('Crypt') { Legion::Crypt.shutdown if defined?(Legion::Crypt) }
      Legion::Readiness.mark_not_ready(:crypt)

      Legion::Readiness.wait_until_not_ready(:transport, :data, :cache, :crypt)

      Legion::Settings.load(force: true, config_dirs: Legion::Settings::Loader.default_directories.select { |d| Dir.exist?(d) })
      Legion::Readiness.mark_ready(:settings)

      Legion::Crypt.start if defined?(Legion::Crypt)
      Legion::Readiness.mark_ready(:crypt)
      # Phase 5: fetch bootstrap RMQ creds after Vault reconnects on reload.
      fetch_phase5_bootstrap_creds

      # Resolve lease:// URIs with freshly loaded settings + new Vault token.
      Legion::Settings.resolve_secrets! if Legion::Settings.respond_to?(:resolve_secrets!)

      setup_transport
      Legion::Readiness.mark_ready(:transport)
      teardown_logging_transport
      setup_logging_transport

      Legion::Identity::Process.refresh_credentials if defined?(Legion::Identity::Process)

      require 'legion/cache' unless defined?(Legion::Cache)
      Legion::Cache.setup
      Legion::Readiness.mark_ready(:cache)

      setup_data
      Legion::Readiness.mark_ready(:data)

      if defined?(Legion::Rbac)
        setup_rbac
      else
        Legion::Readiness.mark_skipped(:rbac)
      end

      if defined?(Legion::LLM)
        setup_llm
      else
        Legion::Readiness.mark_skipped(:llm)
      end

      if defined?(Legion::Apollo)
        setup_apollo
        Legion::Readiness.mark_ready(:apollo)
      else
        Legion::Readiness.mark_skipped(:apollo)
      end

      if defined?(Legion::Gaia)
        setup_gaia
        Legion::Readiness.mark_ready(:gaia)
      else
        Legion::Readiness.mark_skipped(:gaia)
      end

      # Phase 5: re-run identity resolution + credential swap so the reloaded
      # process gets identity-scoped RMQ creds (not stale bootstrap creds).
      setup_identity

      setup_supervision
      load_extensions
      Legion::Readiness.mark_ready(:extensions)

      Legion::Extensions.flush_pending_registrations! if defined?(Legion::Extensions) && Legion::Extensions.respond_to?(:flush_pending_registrations!)

      register_core_tools

      Legion::Crypt.cs
      setup_apm if @api_enabled
      setup_api if @api_enabled

      if defined?(Legion::MCP)
        Legion::MCP.reset!
        Legion::MCP.server if Legion::MCP.respond_to?(:server)
      end
      setup_network_watchdog
      Legion::Settings[:client][:ready] = true
      Legion::Events.emit('service.ready')
      log.info 'Legion has been reloaded'
    ensure
      @reloading = false
    end

    def load_extensions
      require 'legion/runner'
      Legion::Extensions.hook_extensions
    end

    def register_core_tools
      require 'legion/tools'
      Legion::Tools.register_all
      Legion::Tools::Discovery.discover_and_register
      Legion::Tools::EmbeddingCache.setup

      log.info(
        "Tools registered: #{Legion::Tools::Registry.tools.size} always, " \
        "#{Legion::Tools::Registry.deferred_tools.size} deferred"
      )
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.register_core_tools')
    end

    def setup_generated_functions
      return unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)

      loaded = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.load_on_boot
      log.info("Loaded #{loaded} generated functions") if loaded.to_i.positive?
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_generated_functions')
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
      log.info '[mTLS] CertRotation started'
    rescue LoadError => e
      handle_exception(e, level: :warn, operation: 'service.setup_mtls_rotation', availability: 'missing')
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_mtls_rotation')
    end

    def shutdown_mtls_rotation
      return unless @cert_rotation

      @cert_rotation.stop
      @cert_rotation = nil
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.shutdown_mtls_rotation')
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
        log.info(message)
      else
        $stdout.puts "[Legion] #{message}"
      end
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'service.log_privacy_mode_status') if defined?(Legion::Logging)
      nil
    end

    def shutdown_component(name, timeout: 5, &)
      Timeout.timeout(timeout, &)
    rescue Timeout::Error
      log.warn "#{name} shutdown timed out after #{timeout}s, forcing"
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.shutdown_component', component: name, timeout: timeout)
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
            log.info '[Watchdog] Network restored, triggering reload'
            Thread.new { Legion.reload } unless @reloading
          end
        else
          count = @consecutive_failures.increment
          log.warn "[Watchdog] Network check failed (#{count}/#{threshold})"
          if count == threshold
            log.error '[Watchdog] Network failure threshold reached, pausing actors'
            Legion::Extensions.pause_actors if Legion::Extensions.respond_to?(:pause_actors)
          end
        end
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'service.network_watchdog.check')
      end
      @network_watchdog.execute
      log.info "[Watchdog] Network watchdog started (interval=#{interval}s, threshold=#{threshold})"
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.setup_network_watchdog')
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
    rescue StandardError => e
      handle_exception(e, level: :debug, operation: 'service.network_healthy?')
      false
    end

    private

    # Phase 5: fetch short-lived bootstrap RMQ credentials from Vault.
    # Called after Crypt.start (boot) and after Crypt.start (reload).
    # Service owns the gate so Crypt.fetch_bootstrap_rmq_creds can be unconditional.
    def fetch_phase5_bootstrap_creds
      return unless defined?(Legion::Crypt)
      return unless Legion::Crypt.respond_to?(:fetch_bootstrap_rmq_creds)
      return unless Legion::Crypt.respond_to?(:vault_connected?) && Legion::Crypt.vault_connected?
      return unless Legion::Crypt.respond_to?(:dynamic_rmq_creds?) && Legion::Crypt.dynamic_rmq_creds?

      Legion::Crypt.fetch_bootstrap_rmq_creds
    end

    def resolve_identity_providers
      # Phase 4 adds lex-identity-* providers. For now, check if any are loaded.
      return false unless defined?(Legion::Extensions)

      providers = find_identity_providers
      return false if providers.empty?

      # Parallel resolution with 5s per-provider timeout (NO Timeout.timeout — uses future.value)
      pool = Concurrent::FixedThreadPool.new([providers.size, 4].min)
      futures = providers.map do |provider|
        Concurrent::Promises.future_on(pool, provider, &:resolve)
      end

      winner_pair = providers.zip(futures).find do |_provider, future|
        result = begin
          future.value(5) # 5s timeout per provider
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'service.resolve_identity_providers.future')
          nil
        end
        result.is_a?(Hash) && result[:canonical_name]
      end

      if winner_pair
        provider, future = winner_pair
        identity = future.value
        Legion::Identity::Process.bind!(provider, identity)
        log.info "[Identity] resolved via #{provider.class.name}: #{identity[:canonical_name]}"
        true
      else
        false
      end
    rescue StandardError => e
      handle_exception(e, level: :warn, operation: 'service.resolve_identity_providers')
      false
    ensure
      pool&.shutdown
      pool&.kill unless pool&.wait_for_termination(2)
    end

    def find_identity_providers
      return [] unless defined?(Legion::Extensions)

      collect_identity_providers(Legion::Extensions)
    end

    def collect_identity_providers(namespace, visited = Set.new)
      return [] unless namespace.is_a?(Module)
      return [] if visited.include?(namespace.object_id)

      visited.add(namespace.object_id)
      providers = []

      namespace.constants(false).each do |const_name|
        mod = namespace.const_get(const_name, false)
        next unless mod.is_a?(Module)

        providers << mod if mod.respond_to?(:resolve) && mod.respond_to?(:provider_name)
        providers.concat(collect_identity_providers(mod, visited))
      rescue StandardError
        next
      end

      providers
    end

    def bootstrap_log_level(cli_level)
      cli_level = nil if cli_level.respond_to?(:empty?) && cli_level.empty?
      return cli_level if cli_level

      raw_logging = (Legion::Settings[:logging] if defined?(Legion::Settings) && Legion::Settings.respond_to?(:[]))

      level = raw_logging[:level] if raw_logging.is_a?(Hash)
      level || Legion::Logging::Settings.default[:level] || 'info'
    end

    def resolve_logger_settings
      raw_logging = (Legion::Settings[:logging] if defined?(Legion::Settings) && Legion::Settings.respond_to?(:[]))
      raw_logging.is_a?(Hash) ? raw_logging : Legion::Logging::Settings.default
    end

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
      key = tls[:key]

      unless cert && !cert.to_s.empty? && key && !key.to_s.empty?
        log.warn 'api.tls enabled but cert or key is missing — falling back to plain HTTP'
        return nil
      end

      {
        cert:        cert,
        key:         key,
        ca:          tls[:ca],
        verify_mode: verify_mode_for(tls[:verify])
      }.compact
    end

    def build_apm_config(apm)
      {
        server_url:               apm[:server_url] || 'http://localhost:8200',
        api_key:                  apm[:api_key],
        secret_token:             apm[:secret_token],
        api_buffer_size:          apm[:api_buffer_size] || 256,
        api_request_size:         apm[:api_request_size] || '750kb',
        api_request_time:         apm[:api_request_time] || '10s',
        capture_body:             apm.fetch(:capture_body, 'off'),
        capture_headers:          apm.fetch(:capture_headers, true),
        capture_env:              apm.fetch(:capture_env, true),
        disable_send:             apm.fetch(:disable_send, false),
        environment:              apm[:environment] || Legion::Settings[:environment] || 'development',
        framework_name:           'LegionIO',
        framework_version:        Legion::VERSION,
        hostname:                 apm[:hostname] || Legion::Settings[:client][:name],
        ignore_url_patterns:      apm[:ignore_url_patterns] || %w[/api/health /api/ready],
        logger:                   Legion::Logging.log,
        pool_size:                apm[:pool_size] || 1,
        service_name:             apm[:service_name] || 'LegionIO',
        service_node_name:        apm[:service_node_name] || Legion::Settings[:client][:name],
        service_version:          apm[:service_version] || Legion::VERSION,
        transaction_sample_rate:  apm[:sample_rate] || 1.0,
        verify_server_cert:       apm.fetch(:verify_server_cert, true),
        central_config:           apm.fetch(:central_config, true),
        span_frames_min_duration: apm[:span_frames_min_duration]
      }.compact
    end

    def ssl_server_settings(tls_cfg, bind, port)
      return {} unless tls_cfg

      { binds: ["ssl://#{bind}:#{port}?cert=#{tls_cfg[:cert]}&key=#{tls_cfg[:key]}"] }
    end

    def verify_mode_for(verify)
      case verify.to_s
      when 'none' then 'none'
      when 'mutual' then 'force_peer'
      else 'peer'
      end
    end
  end
end
