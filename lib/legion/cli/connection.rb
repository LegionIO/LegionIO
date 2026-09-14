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
          ensure_crypt_for_placeholders
          require 'legion/data'
          # `Legion::Data.skip_migrations?` gates auto-migration on `Legion::Mode.infra?`, but only
          # `if defined?(Legion::Mode)`. Nothing on a CLI path requires it, so the gate never
          # evaluates and an agent-mode CLI attempts `CREATE TABLE schema_info` on a shared
          # database it holds no CREATE grant on. Requiring it lets the existing gate work.
          require 'legion/mode'
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
          ensure_crypt_for_placeholders
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

        # Sections whose credentials arrive as `lease://` / `vault://` placeholders.
        PLACEHOLDER_SECTIONS = %i[data transport cache crypt].freeze

        # Start Crypt — and re-resolve secrets — only when the loaded settings still hold
        # unresolved `lease://` / `vault://` URIs.
        #
        # `ensure_settings` calls `Settings.resolve_secrets!` before any Vault client exists, so
        # those URIs survive as literal strings and are handed to Postgres/RabbitMQ as
        # credentials (`403 ACCESS_REFUSED — Username: lease://rabbitmq#username`). `ensure_crypt`
        # already re-resolves after starting Crypt, but nothing ever called it. `Legion::Service`
        # gets this right by ordering Crypt (phase 3) ahead of transport (4) and data (6); this
        # gives the CLI the same ordering lazily.
        #
        # Non-fatal by design: `LEGION_MODE=lite` has no Vault, and a config with no placeholders
        # must not pay for a Vault round-trip. On failure we fall through and let the subsystem
        # report its own connection error.
        def ensure_crypt_for_placeholders
          return if @crypt_ready
          return unless unresolved_placeholders?

          ensure_crypt
        rescue StandardError => e
          Legion::Logging.warn("Connection: crypt init for lease resolution failed: #{e.message}") if defined?(Legion::Logging)
        end

        def unresolved_placeholders?
          PLACEHOLDER_SECTIONS.any? { |section| placeholder?(Legion::Settings[section]) }
        rescue StandardError
          false
        end

        def placeholder?(node)
          case node
          when String then node.start_with?('lease://', 'vault://')
          when Hash   then node.any? { |_key, value| placeholder?(value) }
          when Array  then node.any? { |value| placeholder?(value) }
          else false
          end
        end

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
