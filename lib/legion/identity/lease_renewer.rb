# frozen_string_literal: true

require 'concurrent'

module Legion
  module Identity
    class LeaseRenewer
      attr_reader :provider_name

      BACKOFF_SLEEP  = 5
      MIN_SLEEP      = 1
      DEFAULT_SLEEP  = 60

      def initialize(provider_name:, provider:, lease:)
        @provider_name = provider_name
        @provider      = provider
        @lease         = Concurrent::AtomicReference.new(lease)
        @stop          = Concurrent::AtomicBoolean.new(false)
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

      private

      def run_loop
        until @stop.true?
          lease      = @lease.get
          sleep_time = compute_sleep(lease)
          interruptible_sleep(sleep_time)
          break if @stop.true?

          renew
        end
      end

      def renew
        new_lease = @provider.provide_token
        @lease.set(new_lease) if new_lease&.valid?
      rescue StandardError => e
        log_renewal_failure(e)
        interruptible_sleep(BACKOFF_SLEEP)
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
        message = "[LeaseRenewer][#{@provider_name}] renewal failed: #{error.message}"
        if defined?(Legion::Logging) && Legion::Logging.respond_to?(:warn)
          Legion::Logging.warn(message)
        else
          $stderr.puts message # rubocop:disable Style/StderrPuts
        end
      end
    end
  end
end
