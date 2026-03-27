# frozen_string_literal: true

module Legion
  module CLI
    module Check
      CHECKS = %i[settings crypt transport cache cache_local data data_local].freeze
      EXTENSION_CHECKS = %i[extensions].freeze
      FULL_CHECKS = %i[api].freeze

      CHECK_LABELS = {
        settings:    'Legion::Settings',
        crypt:       'Legion::Crypt',
        transport:   'Legion::Transport',
        cache:       'Legion::Cache',
        cache_local: 'Legion::Cache::Local',
        data:        'Legion::Data',
        data_local:  'Legion::Data::Local',
        extensions:  'Legion::Extensions',
        api:         'Legion::API'
      }.freeze

      # Dependencies: if a check fails, these dependents are skipped
      DEPENDS_ON = {
        crypt:       :settings,
        transport:   :settings,
        cache:       :settings,
        cache_local: :cache,
        data:        :settings,
        data_local:  :data,
        extensions:  :transport,
        api:         :transport
      }.freeze

      autoload :PrivacyCheck, 'legion/cli/check/privacy_check'

      PROBE_LABELS = {
        flag_set:              'Privacy flag set',
        no_cloud_keys:         'No cloud API keys configured',
        no_external_endpoints: 'External endpoints unreachable'
      }.freeze

      class << self
        def run_privacy(formatter, options)
          require 'legion/settings'
          dir = Connection.send(:resolve_config_dir)
          Legion::Settings.load(config_dir: dir)

          checker = PrivacyCheck.new
          results = checker.run

          if options[:json]
            formatter.json({ results: results, overall: checker.overall_pass? ? 'pass' : 'fail' })
            return checker.overall_pass? ? 0 : 1
          end

          formatter.header('Enterprise Privacy Mode Check')
          formatter.spacer

          results.each do |probe, status|
            label = PROBE_LABELS.fetch(probe, probe.to_s).ljust(36)
            case status
            when :pass
              puts "  #{label}#{formatter.colorize('pass', :green)}"
            when :fail
              puts "  #{label}#{formatter.colorize('FAIL', :red)}"
            when :skip
              puts "  #{label}#{formatter.colorize('skip', :yellow)}"
            end
          end

          formatter.spacer
          if checker.overall_pass?
            formatter.success('Privacy mode fully engaged')
          else
            formatter.error('Privacy mode check failed — see items above')
          end

          checker.overall_pass? ? 0 : 1
        end

        def run(formatter, options)
          level = if options[:full]
                    :full
                  elsif options[:extensions]
                    :extensions
                  else
                    :connections
                  end

          checks = CHECKS.dup
          checks.concat(EXTENSION_CHECKS) if %i[extensions full].include?(level)
          checks.concat(FULL_CHECKS) if level == :full

          results = {}
          started = []

          log_level = options[:verbose] ? 'debug' : 'error'
          setup_logging(log_level)

          checks.each do |name|
            dep = DEPENDS_ON[name]
            if dep && results[dep] && %w[fail skip].include?(results[dep][:status])
              results[name] = { status: 'skip', error: "#{dep} failed" }
              print_result(formatter, name, results[name], options) unless options[:json]
              next
            end

            results[name] = run_check(name, options)
            started << name if results[name][:status] == 'pass'
            resolve_secrets_after_crypt(name, results[name])
            print_result(formatter, name, results[name], options) unless options[:json]
          end

          shutdown(started)
          print_summary(formatter, results, level, options)

          results.values.any? { |r| r[:status] == 'fail' } ? 1 : 0
        end

        private

        def setup_logging(log_level)
          require 'legion/logging'
          Legion::Logging.setup(log_level: log_level, level: log_level, trace: false)
        end

        def resolve_secrets_after_crypt(name, result)
          return unless name == :crypt && result[:status] == 'pass'
          return unless Legion::Settings.respond_to?(:resolve_secrets!)

          Legion::Settings.resolve_secrets!
        rescue StandardError => e
          Legion::Logging.warn("Check#run secret resolution failed: #{e.message}") if defined?(Legion::Logging)
        end

        def run_check(name, options)
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          detail = send(:"check_#{name}", options)
          elapsed = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'pass', time: elapsed, detail: detail }
        rescue StandardError, LoadError => e
          elapsed = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'fail', error: e.message, time: elapsed }
        end

        def check_settings(_options)
          require 'legion/settings'
          dir = Connection.send(:resolve_config_dir)
          Legion::Settings.load(config_dir: dir)
          dir || Legion::Settings.instance_variable_get(:@config_dir) || '(default)'
        end

        def check_crypt(_options)
          require 'legion/crypt'
          Legion::Crypt.start
          vault_addr = ENV.fetch('VAULT_ADDR', nil)
          connected = defined?(Legion::Crypt) && Legion::Crypt.respond_to?(:vault_connected?) && Legion::Crypt.vault_connected?
          connected ? "Vault #{vault_addr || 'connected'}" : 'no Vault'
        end

        def check_transport(_options)
          require 'legion/transport'
          Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
          conn = Legion::Settings[:transport][:connection] || {}
          user = conn[:user].to_s
          pass = conn[:password].to_s
          if user.start_with?('lease://', 'vault://') || pass.start_with?('lease://', 'vault://')
            scheme = user[%r{\A[^:]+://}]
            redacted = scheme ? "#{scheme}..." : '(unresolved)'
            raise "credentials not resolved (Vault lease pending) — user: #{redacted}"
          end

          Legion::Transport::Connection.setup
          if Legion::Transport::Connection.lite_mode?
            'InProcess (lite mode)'
          else
            ts = Legion::Settings[:transport] || {}
            host = ts.dig(:connection, :host) || '127.0.0.1'
            port = ts.dig(:connection, :port) || 5672
            vhost = ts.dig(:connection, :vhost) || '/'
            user = ts.dig(:connection, :user) || 'guest'
            "amqp://#{user}@#{host}:#{port}#{vhost}"
          end
        end

        def check_cache(_options)
          require 'legion/cache'
          if defined?(Legion::Cache) && Legion::Cache.respond_to?(:using_memory?) && Legion::Cache.using_memory?
            'Memory (lite mode)'
          else
            cs = Legion::Settings[:cache] || {}
            driver = cs[:driver] || 'dalli'
            servers = Array(cs[:servers] || cs[:server] || ['127.0.0.1'])
            "#{driver} -> #{servers.join(', ')}"
          end
        end

        def check_cache_local(_options)
          raise 'Legion::Cache::Local not available' unless defined?(Legion::Cache::Local) && Legion::Cache::Local.respond_to?(:setup)

          Legion::Cache::Local.setup
          cs = Legion::Settings[:cache_local] || (Legion::Cache::Settings.respond_to?(:local) ? Legion::Cache::Settings.local : {})
          driver = cs[:driver] || 'dalli'
          servers = Array(cs[:servers] || cs[:server] || ['127.0.0.1'])
          "#{driver} -> #{servers.join(', ')}"
        end

        def check_data(_options)
          require 'legion/data'
          Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
          creds = Legion::Settings[:data][:creds] || Legion::Settings[:data] || {}
          db_user = (creds[:user] || creds[:username]).to_s
          db_pass = creds[:password].to_s
          raise_if_unresolved_data_creds(db_user, db_pass)

          Legion::Data.setup
          ds = Legion::Settings[:data] || {}
          adapter = ds[:adapter] || 'sqlite'
          if adapter == 'sqlite'
            db_path = ds[:database] || 'legion.db'
            "sqlite -> #{db_path}"
          else
            host = ds[:host] || '127.0.0.1'
            port = ds[:port]
            database = ds[:database] || 'legion'
            "#{adapter} -> #{host}#{":#{port}" if port}/#{database}"
          end
        end

        def raise_if_unresolved_data_creds(db_user, db_pass)
          return unless db_user.start_with?('lease://', 'vault://') || db_pass.start_with?('lease://', 'vault://')

          unresolved_fields = []
          unresolved_fields << 'user'     if db_user.start_with?('lease://', 'vault://')
          unresolved_fields << 'password' if db_pass.start_with?('lease://', 'vault://')
          scheme_hints = []
          scheme_hints << 'lease://...' if db_user.start_with?('lease://') || db_pass.start_with?('lease://')
          scheme_hints << 'vault://...' if db_user.start_with?('vault://') || db_pass.start_with?('vault://')
          details = "unresolved fields: #{unresolved_fields.join(', ')}"
          details += " (#{scheme_hints.join(', ')})" unless scheme_hints.empty?
          raise "credentials not resolved (Vault lease pending) — #{details}"
        end

        def check_data_local(_options)
          if defined?(Legion::Data::Local) && Legion::Data::Local.respond_to?(:setup)
            Legion::Data::Local.setup unless Legion::Data::Local.respond_to?(:connected?) && Legion::Data::Local.connected?
            db_path = Legion::Data::Local.respond_to?(:db_path) ? Legion::Data::Local.db_path : '~/.legionio/local.db'
            "sqlite -> #{db_path}"
          elsif defined?(Legion::Data)
            'not configured'
          else
            raise 'Legion::Data not available'
          end
        end

        def check_extensions(_options)
          require 'legion/runner'
          Legion::Extensions.hook_extensions
        end

        def check_api(_options)
          require 'legion/api'
          port = (Legion::Settings[:api] || {})[:port] || 4567
          bind = (Legion::Settings[:api] || {})[:bind] || '127.0.0.1'

          Legion::API.set :port, port
          Legion::API.set :bind, bind
          Legion::API.set :server, :puma
          Legion::API.set :environment, :production

          thread = Thread.new { Legion::API.run! }

          deadline = Time.now + 5
          loop do
            break if api_running?
            break if Time.now > deadline

            sleep(0.1)
          end

          raise 'API server did not start within 5 seconds' unless api_running?
        ensure
          if defined?(thread) && thread
            Legion::API.quit! if defined?(Legion::API) && api_running?
            thread.kill
          end
        end

        def api_running?
          defined?(Legion::API) && Legion::API.running?
        rescue StandardError => e
          Legion::Logging.debug("Check#api_running? failed: #{e.message}") if defined?(Legion::Logging)
          false
        end

        def shutdown(started)
          started.reverse_each do |name|
            send(:"shutdown_#{name}")
          rescue StandardError => e
            Legion::Logging.warn("Check#shutdown failed for #{name}: #{e.message}") if defined?(Legion::Logging)
          end
        end

        def shutdown_settings; end

        def shutdown_crypt
          Legion::Crypt.shutdown
        end

        def shutdown_transport
          Legion::Transport::Connection.shutdown
        end

        def shutdown_cache
          Legion::Cache.shutdown
        end

        def shutdown_cache_local
          Legion::Cache::Local.shutdown if defined?(Legion::Cache::Local) && Legion::Cache::Local.respond_to?(:shutdown)
        end

        def shutdown_data
          Legion::Data.shutdown
        end

        def shutdown_data_local
          Legion::Data::Local.shutdown if defined?(Legion::Data::Local) && Legion::Data::Local.respond_to?(:shutdown)
        end

        def shutdown_extensions
          Legion::Extensions.shutdown
        end

        def shutdown_api; end

        def print_result(formatter, name, result, options)
          label = CHECK_LABELS.fetch(name, name.to_s).ljust(22)
          case result[:status]
          when 'pass'
            detail = result[:detail] ? "  #{formatter.colorize(result[:detail].to_s, :muted)}" : ''
            line = "  #{label} #{formatter.colorize('pass', :green)}#{detail}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'fail'
            line = "  #{label} #{formatter.colorize('FAIL', :red)}  #{result[:error]}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'skip'
            line = "  #{label} #{formatter.colorize('skip', :yellow)}  #{result[:error]}"
          end
          puts line
        end

        def print_summary(formatter, results, level, options)
          passed = results.values.count { |r| r[:status] == 'pass' }
          failed = results.values.count { |r| r[:status] == 'fail' }
          skipped = results.values.count { |r| r[:status] == 'skip' }
          total = results.size

          if options[:json]
            formatter.json({
                             results: results.transform_values(&:compact),
                             summary: { passed: passed, failed: failed, skipped: skipped, level: level.to_s }
                           })
          else
            formatter.spacer
            failed_names = results.select { |_, v| v[:status] == 'fail' }.keys.join(', ')
            msg = "#{passed}/#{total} passed"
            msg += " (#{failed_names} failed)" if failed.positive?
            msg += " (#{skipped} skipped)" if skipped.positive?

            if failed.positive?
              formatter.error(msg)
            else
              formatter.success(msg)
            end
          end
        end
      end
    end
  end
end
