# frozen_string_literal: true

module Legion
  module Region
    module Failover
      module_function

      MAX_LAG_SECONDS = 30

      def promote!(region:)
        validate_target!(region)

        lag = replication_lag
        raise LagTooHighError, "replication lag #{lag.round(1)}s exceeds #{MAX_LAG_SECONDS}s threshold" if lag && lag > MAX_LAG_SECONDS

        previous = Legion::Settings.dig(:region, :primary)
        Legion::Settings[:region][:primary] = region
        Legion::Events.emit('region.failover', from: previous, to: region) if defined?(Legion::Events)

        { promoted: region, previous: previous, lag_seconds: lag }
      end

      def replication_lag
        return nil unless defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection

        row = Legion::Data.connection.fetch(
          'SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag'
        ).first
        row[:lag]&.to_f
      rescue StandardError
        nil
      end

      def validate_target!(region)
        peers = Legion::Settings.dig(:region, :peers) || []
        failover = Legion::Settings.dig(:region, :failover)
        known = (peers + [failover].compact).uniq

        return if known.include?(region)

        raise UnknownRegionError, "'#{region}' is not a known peer or failover region (known: #{known.join(', ')})"
      end

      class LagTooHighError < StandardError; end
      class UnknownRegionError < StandardError; end
    end
  end
end
