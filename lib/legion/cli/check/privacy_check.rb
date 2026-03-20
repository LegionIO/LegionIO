# frozen_string_literal: true

module Legion
  module CLI
    module Check
      class PrivacyCheck
        CLOUD_PROVIDERS = %i[bedrock anthropic openai gemini azure].freeze

        def run
          @results = {}
          @results[:flag_set]              = check_flag_set
          @results[:no_cloud_keys]         = check_no_cloud_keys
          @results[:no_external_endpoints] = check_no_external_endpoints
          @results
        end

        def overall_pass?
          run.values.all? { |v| v == :pass }
        end

        private

        def check_flag_set
          if settings_loaded? && Legion::Settings.enterprise_privacy?
            :pass
          else
            :fail
          end
        end

        def check_no_cloud_keys
          llm = Legion::Settings[:llm]
          return :pass unless llm.is_a?(Hash)

          providers = (llm[:providers] || llm['providers'] || {}).transform_keys(&:to_sym)
          CLOUD_PROVIDERS.each do |provider|
            cfg = providers[provider]
            return :fail if raw_credential?(cfg)
          end

          :pass
        rescue StandardError
          :skip
        end

        def raw_credential?(cfg)
          return false unless cfg.is_a?(Hash)

          key = cfg[:api_key] || cfg['api_key'] ||
                cfg[:bearer_token] || cfg['bearer_token'] ||
                cfg[:secret_key] || cfg['secret_key']

          key.is_a?(String) && !key.empty? && !key.start_with?('env://', 'vault://')
        end

        def check_no_external_endpoints
          endpoints = [
            ['api.anthropic.com', 443],
            ['api.openai.com', 443],
            ['generativelanguage.googleapis.com', 443]
          ]
          endpoints.each do |host, port|
            return :fail if tcp_reachable?(host, port)
          end
          :pass
        rescue StandardError
          :skip
        end

        def tcp_reachable?(host, port)
          socket = ::TCPSocket.new(host, port)
          socket.close
          true
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError, Errno::ENETUNREACH
          false
        end

        def settings_loaded?
          defined?(Legion::Settings) && Legion::Settings.respond_to?(:enterprise_privacy?)
        rescue StandardError
          false
        end
      end
    end
  end
end
