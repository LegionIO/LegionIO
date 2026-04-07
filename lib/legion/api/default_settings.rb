# frozen_string_literal: true

require 'sinatra/base'

module Legion
  class API < Sinatra::Base
    module Settings
      def self.default
        {
          enabled:         true,
          port:            4567,
          bind:            '127.0.0.1',
          puma:            puma_defaults,
          bind_retries:    3,
          bind_retry_wait: 2,
          tls:             tls_defaults,
          elastic_apm:     elastic_apm_defaults
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

      def self.elastic_apm_defaults
        {
          enabled:                  false,
          server_url:               'http://localhost:8200',
          api_key:                  nil,
          secret_token:             nil,
          api_buffer_size:          256,
          api_request_size:         '750kb',
          api_request_time:         '10s',
          capture_body:             'off',
          capture_headers:          true,
          capture_env:              true,
          disable_send:             false,
          environment:              nil,
          hostname:                 nil,
          ignore_url_patterns:      %w[/api/health /api/ready],
          pool_size:                1,
          service_name:             'LegionIO',
          service_node_name:        nil,
          service_version:          nil,
          sample_rate:              1.0,
          verify_server_cert:       true,
          central_config:           true,
          span_frames_min_duration: '5ms'
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
