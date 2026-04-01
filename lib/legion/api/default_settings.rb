# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Settings
      def self.default
        {
          enabled:         true,
          port:            4567,
          bind:            '0.0.0.0',
          puma:            puma_defaults,
          bind_retries:    3,
          bind_retry_wait: 2,
          tls:             tls_defaults
        }
      end

      def self.puma_defaults
        {
          min_threads:        10,
          max_threads:        16,
          persistent_timeout: 20,
          first_data_timeout: 30
        }
      end

      def self.tls_defaults
        {
          enabled: false
        }
      end
    end
  end
end

begin
  Legion::Settings.merge_settings('api', Legion::API::Settings.default) if Legion.const_defined?('Settings', false)
rescue StandardError => e
  if Legion.const_defined?('Logging', false) && Legion::Logging.respond_to?(:fatal)
    Legion::Logging.fatal(e.message)
    Legion::Logging.fatal(e.backtrace)
  else
    puts e.message
    puts e.backtrace
  end
end
