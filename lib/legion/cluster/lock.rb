# frozen_string_literal: true

module Legion
  module Cluster
    module Lock
      module_function

      def acquire(name:, timeout: 5) # rubocop:disable Lint/UnusedMethodArgument
        key = lock_key(name)
        db = Legion::Data.connection
        return false unless db

        db.fetch('SELECT pg_try_advisory_lock(?) AS acquired', key).first[:acquired]
      rescue StandardError
        false
      end

      def release(name:)
        key = lock_key(name)
        db = Legion::Data.connection
        return false unless db

        db.fetch('SELECT pg_advisory_unlock(?) AS released', key).first[:released]
      rescue StandardError
        false
      end

      def with_lock(name:, timeout: 5)
        acquired = acquire(name: name, timeout: timeout)
        return unless acquired

        begin
          yield
        ensure
          release(name: name)
        end
      end

      def lock_key(name)
        name.to_s.bytes.reduce(0) { |acc, b| ((acc * 31) + b) & 0x7FFFFFFF }
      end
    end
  end
end
