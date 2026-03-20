# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Actors
      module Fingerprint
        def skip_if_unchanged?
          false
        end

        def fingerprint_source
          bucket = respond_to?(:time) ? time.to_i : 60
          bucket = 1 if bucket < 1
          (Time.now.utc.to_i / bucket).to_s
        end

        def compute_fingerprint
          Digest::SHA256.hexdigest(fingerprint_source.to_s)
        end

        def unchanged?
          return false if @last_fingerprint.nil?

          compute_fingerprint == @last_fingerprint
        end

        def store_fingerprint!
          @last_fingerprint = compute_fingerprint
        end

        def skip_or_run
          if skip_if_unchanged? && unchanged?
            Legion::Logging.debug "#{self.class} skipped: fingerprint unchanged (#{@last_fingerprint[0, 8]}...)"
            return
          end

          yield
          store_fingerprint!
        end
      end
    end
  end
end
