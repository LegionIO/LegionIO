# frozen_string_literal: true

module Legion
  module CLI
    module Check
      CHECKS = %i[settings crypt transport cache data].freeze
      EXTENSION_CHECKS = %i[extensions].freeze
      FULL_CHECKS = %i[api].freeze

      # Dependencies: if a check fails, these dependents are skipped
      DEPENDS_ON = {
        crypt:      :settings,
        transport:  :settings,
        cache:      :settings,
        data:       :settings,
        extensions: :transport,
        api:        :transport
      }.freeze

      class << self
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
            if dep && results[dep] && results[dep][:status] == 'fail'
              results[name] = { status: 'skip', error: "#{dep} failed" }
              print_result(formatter, name, results[name], options) unless options[:json]
              next
            end

            results[name] = run_check(name, options)
            started << name if results[name][:status] == 'pass'
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

        def run_check(name, options)
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          send(:"check_#{name}", options)
          elapsed = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'pass', time: elapsed }
        rescue StandardError, LoadError => e
          elapsed = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(2)
          { status: 'fail', error: e.message, time: elapsed }
        end

        def check_settings(_options)
          require 'legion/settings'
          dir = Connection.send(:resolve_config_dir)
          Legion::Settings.load(config_dir: dir)
        end

        def check_crypt(_options)
          require 'legion/crypt'
          Legion::Crypt.start
        end

        def check_transport(_options)
          require 'legion/transport'
          Legion::Settings.merge_settings('transport', Legion::Transport::Settings.default)
          Legion::Transport::Connection.setup
        end

        def check_cache(_options)
          require 'legion/cache'
        end

        def check_data(_options)
          require 'legion/data'
          Legion::Settings.merge_settings(:data, Legion::Data::Settings.default)
          Legion::Data.setup
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
        rescue StandardError
          false
        end

        def shutdown(started)
          started.reverse_each do |name|
            send(:"shutdown_#{name}")
          rescue StandardError
            # best-effort cleanup
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

        def shutdown_data
          Legion::Data.shutdown
        end

        def shutdown_extensions
          Legion::Extensions.shutdown
        end

        def shutdown_api; end

        def print_result(formatter, name, result, options)
          label = name.to_s.ljust(14)
          case result[:status]
          when 'pass'
            line = "  #{label}#{formatter.colorize('pass', :green)}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'fail'
            line = "  #{label}#{formatter.colorize('FAIL', :red)}  #{result[:error]}"
            line += "  (#{result[:time]}s)" if options[:verbose]
          when 'skip'
            line = "  #{label}#{formatter.colorize('skip', :yellow)}  #{result[:error]}"
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
