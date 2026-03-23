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

        def ensure_settings
          return if @settings_ready

          ensure_logging
          require 'legion/settings'

          dir = resolve_config_dir
          Legion::Settings.load(config_dir: dir)
          @settings_ready = true
        end

        def ensure_data
          return if @data_ready

          ensure_settings
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
          @crypt_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-crypt gem is not installed (gem install legion-crypt)'
        rescue StandardError => e
          raise CLI::Error, "crypt initialization failed: #{e.message}"
        end

        def ensure_cache
          return if @cache_ready

          ensure_settings
          require 'legion/cache'
          @cache_ready = true
        rescue LoadError
          raise CLI::Error, 'legion-cache gem is not installed (gem install legion-cache)'
        end

        def ensure_llm
          return if @llm_ready

          ensure_settings
          require 'legion/llm'
          Legion::Settings.merge_settings(:llm, Legion::LLM::Settings.default)
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
          if @config_dir.is_a?(String) && !@config_dir.strip.empty?
            expanded = File.expand_path(@config_dir)
            return expanded if Dir.exist?(expanded)
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
