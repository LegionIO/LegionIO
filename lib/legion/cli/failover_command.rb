# frozen_string_literal: true

require 'thor'
require 'legion/cli/output'
require 'legion/cli/connection'

module Legion
  module CLI
    class Failover < Thor
      namespace 'failover'

      class_option :json, type: :boolean, default: false, desc: 'Output as JSON'
      class_option :no_color, type: :boolean, default: false, desc: 'Disable color output'

      desc 'promote', 'Promote a region to primary'
      option :region, type: :string, required: true, desc: 'Target region to promote'
      option :dry_run, type: :boolean, default: false, desc: 'Show replication lag without promoting'
      option :force, type: :boolean, default: false, desc: 'Force promotion even if lag exceeds threshold'
      def promote
        out = formatter
        ensure_settings

        target = options[:region]
        require 'legion/region/failover'

        if options[:dry_run]
          run_dry_run(out, target)
        else
          run_promote(out, target)
        end
      rescue Legion::Region::Failover::UnknownRegionError => e
        out.error(e.message)
        raise SystemExit, 1
      rescue Legion::Region::Failover::LagTooHighError => e
        if options[:force]
          out.warn("#{e.message} — forcing promotion")
          force_promote(out, target)
        else
          out.error("#{e.message}. Use --force to override.")
          raise SystemExit, 1
        end
      end

      desc 'status', 'Show current region configuration'
      def status
        out = formatter
        ensure_settings

        region_config = Legion::Settings[:region] || {}
        if options[:json]
          out.json(region_config)
        else
          out.header('Region Configuration')
          out.detail({
                       current:          region_config[:current] || '(not set)',
                       primary:          region_config[:primary] || '(not set)',
                       failover:         region_config[:failover] || '(not set)',
                       peers:            (region_config[:peers] || []).join(', ').then { |s| s.empty? ? '(none)' : s },
                       default_affinity: region_config[:default_affinity] || 'prefer_local'
                     })
        end
      end

      no_commands do
        def formatter
          @formatter ||= Output::Formatter.new(
            json:  options[:json],
            color: !options[:no_color]
          )
        end

        private

        def ensure_settings
          Connection.ensure_settings(resolve_secrets: false)
        end

        def run_dry_run(out, target)
          Legion::Region::Failover.validate_target!(target)
          lag = Legion::Region::Failover.replication_lag

          if options[:json]
            out.json({ target: target, lag_seconds: lag, dry_run: true })
          else
            out.header('Failover Dry Run')
            lag_str = lag ? "#{lag.round(1)}s" : '(unavailable — no DB connection)'
            out.detail({ target: target, replication_lag: lag_str })
            if lag && lag > Legion::Region::Failover::MAX_LAG_SECONDS
              out.warn("Lag exceeds #{Legion::Region::Failover::MAX_LAG_SECONDS}s threshold")
            else
              out.success('Lag within acceptable range')
            end
          end
        end

        def run_promote(out, target)
          result = Legion::Region::Failover.promote!(region: target)
          if options[:json]
            out.json(result)
          else
            out.success("Region promoted: #{result[:previous]} -> #{result[:promoted]}")
            lag_str = result[:lag_seconds] ? "#{result[:lag_seconds].round(1)}s" : '(unavailable)'
            out.detail({ promoted: result[:promoted], previous: result[:previous], replication_lag: lag_str })
          end
        end

        def force_promote(out, target)
          previous = Legion::Settings.dig(:region, :primary)
          lag = Legion::Region::Failover.replication_lag
          Legion::Settings[:region][:primary] = target
          Legion::Events.emit('region.failover', from: previous, to: target) if defined?(Legion::Events)

          result = { promoted: target, previous: previous, lag_seconds: lag, forced: true }
          if options[:json]
            out.json(result)
          else
            out.success("Region force-promoted: #{previous} -> #{target}")
          end
        end
      end
    end
  end
end
