# frozen_string_literal: true

module Legion
  module CLI
    # Lazy connection manager for CLI commands.
    # Only connects to the subsystems a command actually needs,
    # instead of booting the entire Legion::Service.
    module Connection
      class << self
        attr_accessor :config_dir

        attr_writer :log_level

        def log_level
          @log_level || 'error'
        end

        def ensure_logging
          return if @logging_ready

          require 'legion/logging'
          Legion::Logging.setup(log_level: log_level, level: log_level, trace: false)
          @logging_ready = true
        end

        def ensure_settings(resolve_secrets: true)
          return if @settings_ready

          ensure_logging
          require 'legion/settings'

          dir = resolve_config_dir
          Legion::Settings.load(config_dir: dir)
          Legion::Settings.resolve_secrets! if resolve_secrets && Legion::Settings.respond_to?(:resolve_secrets!)
          @settings_ready = true
        end

        def ensure_data
          return if @data_ready

          ensure_settings
          ensure_secrets_resolved
          require 'legion/data'
          Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
          Legion::Data.setup
          @data_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-data gem is not installed (gem install legion-data)'
        rescue StandardError => e
          raise CLI::Error, "database connection failed: #{e.message}"
        end

        def ensure_transport
          return if @transport_ready

          ensure_settings
          ensure_secrets_resolved
          require 'legion/transport'
          Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
          Legion::Transport::Connection.setup
          @transport_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-transport gem is not installed (gem install legion-transport)'
        rescue StandardError => e
          raise CLI::Error, "transport connection failed: #{e.message}"
        end

        def ensure_crypt
          return if @crypt_ready

          ensure_settings
          require 'legion/crypt'
          Legion::Crypt.start
          # Re-resolve now that LeaseManager is available for lease:// URIs
          Legion::Settings.resolve_secrets! if Legion::Settings.respond_to?(:resolve_secrets!)
          @crypt_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-crypt gem is not installed (gem install legion-crypt)'
        rescue StandardError => e
          raise CLI::Error, "crypt initialization failed: #{e.message}"
        end

        # Resolve lease:// and vault:// credential references before a direct
        # backend connection. Mirrors the daemon boot order (Crypt.start ->
        # resolve_secrets! -> connect): short-lived CLI processes must start
        # Crypt so the LeaseManager/Vault client exists, otherwise unresolved
        # lease:// strings are passed verbatim to the database/broker driver.
        #
        # Skipped when legion-crypt is not installed (e.g. a local-dev bundle
        # with plaintext creds) so data/transport still connect. A genuine Crypt
        # failure still surfaces via ensure_crypt as a CLI::Error.
        def ensure_secrets_resolved
          return if @crypt_ready
          return unless crypt_available?

          ensure_crypt
        end

        def crypt_available?
          Gem::Specification.find_by_name('legion-crypt')
          true
        rescue Gem::MissingSpecError
          false
        end

        def ensure_cache
          return if @cache_ready

          ensure_settings
          require 'legion/cache'
          @cache_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-cache gem is not installed (gem install legion-cache)'
        end

        def ensure_knowledge
          return if @knowledge_ready

          ensure_settings
          spec = Gem::Specification.find_by_name('lex-knowledge')
          require "#{spec.gem_dir}/lib/legion/extensions/knowledge"
          @knowledge_ready = true
        rescue Gem::MissingSpecError
          raise CLI::Error, 'lex-knowledge gem is not installed (gem install lex-knowledge)'
        end

        # Merge Legion::LLM::Settings.default into the :llm namespace without
        # booting the local LLM stack. This is all the daemon-routing CLI paths
        # (chat prompt / ask) need: the merge populates llm.daemon.url so
        # Legion::LLM::Call::DaemonClient.available? can resolve the daemon.
        # Full local init (providers, discovery, transports) is deliberately
        # skipped — that work already happened in the running daemon.
        def ensure_llm_settings
          return if @llm_settings_ready

          ensure_settings
          require 'legion/llm'
          Legion::Settings.merge_settings(:llm, Legion::LLM::Settings.default)
          @llm_settings_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-llm gem is not installed (gem install legion-llm)'
        rescue StandardError => e
          raise CLI::Error, "LLM settings initialization failed: #{e.message}"
        end

        def ensure_llm
          return if @llm_ready

          ensure_llm_settings
          Legion::LLM.start
          @llm_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-llm gem is not installed (gem install legion-llm)'
        rescue StandardError => e
          raise CLI::Error, "LLM initialization failed: #{e.message}"
        end

        def settings?
          @settings_ready == true
        end

        def data?
          @data_ready == true
        end

        def transport?
          @transport_ready == true
        end

        def llm?
          @llm_ready == true
        end

        def llm_settings?
          @llm_settings_ready == true
        end

        def shutdown
          Legion::LLM.shutdown if @llm_ready
          Legion::Transport::Connection.shutdown if @transport_ready
          Legion::Data.shutdown if @data_ready
          Legion::Cache.shutdown if @cache_ready
          Legion::Crypt.shutdown if @crypt_ready
        rescue StandardError => e
          Legion::Logging.warn("Connection#shutdown cleanup failed: #{e.message}") if defined?(Legion::Logging)
        end

        private

        def resolve_config_dir
          if @config_dir.is_a?(String)
            stripped = @config_dir.strip
            unless stripped.empty?
              expanded = File.expand_path(stripped)
              return expanded if Dir.exist?(expanded)
            end
          end

          require 'legion/settings/loader' unless defined?(Legion::Settings::Loader)
          Legion::Settings::Loader.default_directories.each do |path|
            return path if Dir.exist?(path)
          end

          nil
        end
      end
    end
  end
end
