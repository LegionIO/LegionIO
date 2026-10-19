# frozen_string_literal: true

require 'concurrent'

module Legion
  module Identity
    class LeaseRenewer
      include Legion::Logging::Helper

      attr_reader :provider_name, :provider

      BACKOFF_SLEEP  = 5
      MIN_SLEEP      = 1
      DEFAULT_SLEEP  = 60
      MAX_BACKOFF    = 300

      def initialize(provider_name:, provider:, lease:)
        @provider_name = provider_name
        @provider      = provider
        @lease         = Concurrent::AtomicReference.new(lease)
        @stop          = Concurrent::AtomicBoolean.new(false)
        @failures      = Concurrent::AtomicFixnum.new(0)
        @thread        = Thread.new { run_loop }
        @thread.name   = "lease-renewer-#{provider_name}"
        @thread.abort_on_exception = false
      end

      def current_lease
        @lease.get
      end

      def stop!
        @stop.make_true
        @thread&.wakeup rescue nil # rubocop:disable Style/RescueModifier
        @thread&.join(5)
      end

      def alive?
        @thread&.alive? || false
      end

      def consecutive_failures
        @failures.value
      end

      private

      def run_loop
        until @stop.true?
          lease      = @lease.get
          sleep_time = @failures.value.positive? ? backoff_sleep : compute_sleep(lease)
          interruptible_sleep(sleep_time)
          break if @stop.true?

          renew
        end
      end

      # A nil/invalid lease (e.g. refresh token rejected) or an exception counts as a
      # failure; the next attempt waits backoff_sleep instead of compute_sleep, which
      # for an already-expired lease would be MIN_SLEEP (a 1/sec retry loop).
      def renew
        new_lease = @provider.provide_token
        if new_lease&.valid?
          @lease.set(new_lease)
          @failures.value = 0
        else
          record_failure
        end
      rescue StandardError => e
        log_renewal_failure(e)
        record_failure
      end

      def record_failure
        count = @failures.increment
        return unless count == 1 || (count % 10).zero?

        log.debug("[lease_renewer] action=renew_failed provider=#{@provider_name} failures=#{count} next_retry=#{backoff_sleep}s") if defined?(Legion::Logging)
      end

      # BACKOFF_SLEEP doubling per consecutive failure, capped at MAX_BACKOFF.
      def backoff_sleep
        exponent = [@failures.value - 1, 10].min
        [BACKOFF_SLEEP * (2**exponent), MAX_BACKOFF].min
      end

      def compute_sleep(lease)
        return DEFAULT_SLEEP if lease.nil? || lease.expires_at.nil? || lease.issued_at.nil?

        remaining      = lease.expires_at - Time.now
        half_remaining = remaining / 2.0
        [half_remaining, MIN_SLEEP].max
      end

      def interruptible_sleep(seconds)
        deadline = Time.now + seconds
        sleep([1, deadline - Time.now].min) while Time.now < deadline && !@stop.true?
      end

      def log_renewal_failure(error)
        if defined?(Legion::Logging)
          log.warn("renewal failed: #{error.message}")
        else
          $stderr.puts "[LeaseRenewer][#{@provider_name}] renewal failed: #{error.message}" # rubocop:disable Style/StderrPuts
        end
      end
    end
  end
end
