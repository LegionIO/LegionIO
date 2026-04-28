# frozen_string_literal: true

require 'thor'

module Legion
  module CLI
    class Llm < Thor
      namespace 'llm'

      def self.exit_on_failure?
        true
      end

      class_option :json,       type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color,   type: :boolean, default: false, desc: 'Disable color output'
      class_option :verbose,    type: :boolean, default: false, aliases: ['-V'], desc: 'Verbose logging'
      class_option :config_dir, type: :string,  desc: 'Config directory path'

      desc 'status', 'Show LLM subsystem status and provider health'
      default_task :status
      def status
        out = formatter
        boot_llm_settings

        data = collect_status
        if options[:json]
          out.json(data)
        else
          show_status(out, data)
        end
      end

      desc 'providers', 'List configured LLM providers'
      def providers
        out = formatter
        boot_llm_settings

        data = collect_providers
        if options[:json]
          out.json(providers: data)
        else
          show_providers(out, data)
        end
      end

      desc 'models', 'List available models per provider'
      def models
        out = formatter
        boot_llm_settings

        data = collect_models
        if options[:json]
          out.json(models: data)
        else
          show_models(out, data)
        end
      end

      desc 'ping', 'Test connectivity to each enabled provider'
      option :timeout, type: :numeric, default: 15, desc: 'Timeout per provider in seconds'
      def ping
        out = formatter
        boot_llm(out)

        results = ping_all_providers(out)
        if options[:json]
          out.json(results: results)
        else
          show_ping_results(out, results)
        end
      end

      no_commands do # rubocop:disable Metrics/BlockLength
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def boot_llm_settings
          Connection.config_dir = options[:config_dir] if options[:config_dir]
          Connection.log_level = options[:verbose] ? 'debug' : 'error'
          Connection.ensure_settings
          Legion::Settings.resolve_secrets! if Legion::Settings.respond_to?(:resolve_secrets!)
          require 'legion/llm'
          Legion::Settings.merge_settings(:llm, Legion::LLM::Settings.default)
        end

        def boot_llm(out)
          boot_llm_settings
          out.header('Starting LLM subsystem...') unless options[:json]
          Legion::LLM.start
        rescue StandardError => e
          Legion::Logging.error("LlmCommand#boot_llm failed: #{e.message}") if defined?(Legion::Logging)
          out.error("LLM start failed: #{e.message}") unless options[:json]
        end

        def llm_settings
          Legion::LLM.settings
        end

        def collect_status
          providers_cfg = llm_settings[:providers] || {}
          enabled = providers_cfg.select { |_, c| c[:enabled] }
          started = defined?(Legion::LLM) && Legion::LLM.started?

          {
            started:          started,
            default_model:    llm_settings[:default_model],
            default_provider: llm_settings[:default_provider],
            enabled_count:    enabled.size,
            total_count:      providers_cfg.size,
            providers:        collect_providers,
            routing:          collect_routing,
            system:           collect_system
          }
        end

        def collect_providers
          providers_cfg = llm_settings[:providers] || {}
          providers_cfg.map do |name, cfg|
            enabled = cfg[:enabled] == true
            {
              name:          name,
              enabled:       enabled,
              deferred:      !enabled && unresolved_credentials?(cfg),
              default_model: cfg[:default_model],
              reachable:     check_reachable(name, cfg)
            }
          end
        end

        def unresolved_credentials?(cfg)
          %i[api_key secret_key bearer_token password].any? do |key|
            val = cfg[key].to_s
            val.start_with?('vault://', 'lease://', 'env://')
          end
        end

        def check_reachable(name, cfg)
          case name
          when :ollama
            return false unless cfg[:enabled]

            base = cfg[:base_url] || 'http://localhost:11434'
            uri = URI(base)
            Socket.tcp(uri.host, uri.port, connect_timeout: 2) { true }
          when :bedrock
            return nil unless cfg[:enabled]

            cfg[:bearer_token] || (cfg[:api_key] && cfg[:secret_key]) ? :credentials_present : false
          else
            return nil unless cfg[:enabled]

            cfg[:api_key] ? :credentials_present : false
          end
        rescue StandardError => e
          Legion::Logging.warn("LlmCommand#check_provider_credentials failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def collect_routing
          return { enabled: false } unless defined?(Legion::LLM::Router)

          {
            enabled:    Legion::LLM::Router.routing_enabled?,
            local_tier: Legion::LLM::Router.tier_available?(:local),
            fleet_tier: Legion::LLM::Router.tier_available?(:fleet),
            cloud_tier: Legion::LLM::Router.tier_available?(:cloud)
          }
        rescue StandardError => e
          Legion::Logging.warn("LlmCommand#collect_routing failed: #{e.message}") if defined?(Legion::Logging)
          { enabled: false }
        end

        def collect_system
          return {} unless defined?(Legion::LLM::Discovery::System)

          Legion::LLM::Discovery::System.refresh! if Legion::LLM::Discovery::System.stale?
          {
            platform:        Legion::LLM::Discovery::System.platform,
            total_memory_mb: Legion::LLM::Discovery::System.total_memory_mb,
            avail_memory_mb: Legion::LLM::Discovery::System.available_memory_mb,
            memory_pressure: Legion::LLM::Discovery::System.memory_pressure?
          }
        rescue StandardError => e
          Legion::Logging.warn("LlmCommand#collect_system failed: #{e.message}") if defined?(Legion::Logging)
          {}
        end

        def collect_models
          providers_cfg = llm_settings[:providers] || {}
          result = {}

          providers_cfg.each do |name, cfg|
            next unless cfg[:enabled]

            models = [cfg[:default_model]].compact
            if name == :ollama && defined?(Legion::LLM::Discovery::Ollama)
              begin
                Legion::LLM::Discovery::Ollama.refresh! if Legion::LLM::Discovery::Ollama.stale?
                discovered = Legion::LLM::Discovery::Ollama.model_names
                models = discovered unless discovered.empty?
              rescue StandardError => e
                Legion::Logging.debug("LlmCommand#collect_models ollama discovery failed: #{e.message}") if defined?(Legion::Logging)
              end
            end
            result[name] = models
          end
          result
        end

        def ping_all_providers(out)
          providers_cfg = llm_settings[:providers] || {}
          enabled = providers_cfg.select { |_, c| c[:enabled] }

          if enabled.empty?
            out.warn('No providers enabled') unless options[:json]
            return []
          end

          enabled.map do |name, cfg|
            ping_one_provider(out, name, cfg)
          end
        end

        def ping_one_provider(out, name, cfg)
          model = cfg[:default_model]
          return { provider: name, status: 'skip', message: 'no default model configured', latency_ms: nil } unless model

          out.header("  Pinging #{name} (#{model})...") unless options[:json]
          t0 = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

          response = Legion::LLM.ask_direct(
            message:  'Respond with only the word: pong',
            model:    model,
            provider: name,
            caller:   { source: 'cli', command: 'llm ping' }
          )
          elapsed = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - t0) * 1000).round

          content = response_content(response)
          success = content.downcase.include?('pong')

          if success
            out.success("  #{name}: pong (#{elapsed}ms)") unless options[:json]
          else
            out.warn("  #{name}: unexpected response (#{elapsed}ms): #{content[0..80]}") unless options[:json]
          end

          { provider: name, status: success ? 'ok' : 'unexpected', response: content[0..80],
            model: model, latency_ms: elapsed }
        rescue StandardError => e
          elapsed = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - t0) * 1000).round if t0

          out.error("  #{name}: #{e.message}") unless options[:json]
          { provider: name, status: 'error', message: e.message, model: model, latency_ms: elapsed }
        end

        def response_content(response)
          if response.respond_to?(:content)
            response.content.to_s.strip
          elsif response.is_a?(Hash)
            (response[:content] || response['content'] || response[:response] || response['response']).to_s.strip
          else
            response.to_s.strip
          end
        end

        def show_status(out, data)
          out.header('LLM Status')
          out.detail({
                       'Started'           => data[:started].to_s,
                       'Default Provider'  => (data[:default_provider] || '(none)').to_s,
                       'Default Model'     => (data[:default_model] || '(none)').to_s,
                       'Providers Enabled' => "#{data[:enabled_count]}/#{data[:total_count]}"
                     })

          out.spacer
          show_providers(out, data[:providers])

          routing = data[:routing] || {}
          if routing[:enabled]
            out.spacer
            out.header('Routing')
            out.detail({
                         'Enabled'    => routing[:enabled].to_s,
                         'Local Tier' => routing[:local_tier].to_s,
                         'Fleet Tier' => routing[:fleet_tier].to_s,
                         'Cloud Tier' => routing[:cloud_tier].to_s
                       })
          end

          sys = data[:system] || {}
          return if sys.empty?

          out.spacer
          out.header('System')
          out.detail({
                       'Platform'         => (sys[:platform] || 'unknown').to_s,
                       'Total Memory'     => sys[:total_memory_mb] ? "#{sys[:total_memory_mb]} MB" : 'unknown',
                       'Available Memory' => sys[:avail_memory_mb] ? "#{sys[:avail_memory_mb]} MB" : 'unknown',
                       'Memory Pressure'  => sys[:memory_pressure].to_s
                     })
        end

        def show_providers(out, providers_data)
          out.header('Providers')
          providers_data.each do |p|
            status = if p[:enabled]
                       reach = p[:reachable]
                       case reach
                       when true then 'enabled, reachable'
                       when :credentials_present then 'enabled, credentials present'
                       when false then 'enabled, unreachable'
                       else 'enabled'
                       end
                     elsif p[:deferred]
                       'deferred (credentials pending Vault)'
                     else
                       'disabled'
                     end

            color = if p[:enabled]
                      :green
                    elsif p[:deferred]
                      :yellow
                    else
                      :muted
                    end
            name_str = p[:name].to_s.ljust(12)
            model_str = p[:default_model] ? " (#{p[:default_model]})" : ''
            puts "  #{out.colorize(name_str, :label)}#{out.colorize(status, color)}#{model_str}"
          end
        end

        def show_models(out, models_data)
          out.header('Available Models')
          if models_data.empty?
            out.warn('No providers enabled')
            return
          end

          models_data.each do |provider, model_list|
            out.spacer
            puts "  #{out.colorize(provider.to_s, :accent)} (#{model_list.size} model#{'s' unless model_list.size == 1})"
            model_list.each { |m| puts "    #{m}" }
          end
        end

        def show_ping_results(out, results)
          return if results.empty?

          out.spacer
          out.header('Ping Results')
          passed = 0
          failed = 0

          results.each do |r|
            case r[:status]
            when 'ok'
              passed += 1
            when 'skip'
              puts "  #{out.colorize(r[:provider].to_s.ljust(12), :label)}#{out.colorize('skipped', :muted)} #{r[:message]}"
            else
              failed += 1
            end
          end

          out.spacer
          if failed.zero?
            out.success("#{passed} provider(s) responding")
          else
            out.error("#{failed} provider(s) failed, #{passed} responding")
          end
        end
      end
    end
  end
end
