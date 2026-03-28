# frozen_string_literal: true

require_relative '../definitions'

module Legion
  module Extensions
    module Hooks
      class Base
        extend Legion::Extensions::Definitions
        include Legion::Extensions::Helpers::Lex

        class << self
          # DSL: route based on a request header value
          #   route_header 'X-GitHub-Event',
          #     'push'         => :on_push,
          #     'pull_request' => :on_pull_request
          def route_header(header_name, mapping = {})
            @route_type = :header
            @route_header_name = header_name.upcase.tr('-', '_')
            @route_mapping = mapping.transform_keys(&:to_s)
          end

          # DSL: route based on a payload field value
          #   route_field :event_type,
          #     'build.completed' => :on_build,
          #     'deploy.started'  => :on_deploy
          def route_field(field_name, mapping = {})
            @route_type = :field
            @route_field_name = field_name.to_sym
            @route_mapping = mapping.transform_keys(&:to_s)
          end

          # DSL: verify via HMAC signature (GitHub, Slack, Stripe pattern)
          #   verify_hmac header: 'X-Hub-Signature-256',
          #              secret: :webhook_secret,
          #              algorithm: 'SHA256',
          #              prefix: 'sha256='
          def verify_hmac(header:, secret:, algorithm: 'SHA256', prefix: 'sha256=')
            @verify_type = :hmac
            @verify_config = { header: header.upcase.tr('-', '_'), secret: secret, algorithm: algorithm, prefix: prefix }
          end

          # DSL: verify via bearer/static token in a header
          #   verify_token header: 'Authorization', secret: :webhook_token
          def verify_token(header: 'Authorization', secret: :webhook_token)
            @verify_type = :token
            @verify_config = { header: header.upcase.tr('-', '_'), secret: secret }
          end

          attr_reader :route_type, :route_header_name, :route_field_name,
                      :route_mapping, :verify_type, :verify_config
        end

        # Instance methods called by the API layer

        # Determine which runner function to call.
        # Returns a symbol (function name) or nil (unhandled).
        def route(headers, payload)
          case self.class.route_type
          when :header
            route_by_header(headers)
          when :field
            route_by_field(payload)
          else
            :handle # deprecated fallback; prefer explicit route_header/route_field
          end
        end

        # Verify the request is authentic.
        # Returns true/false.
        def verify(headers, body)
          case self.class.verify_type
          when :hmac
            verify_hmac(headers, body)
          when :token
            verify_token(headers)
          else
            true
          end
        end

        # Which runner class handles this hook's functions.
        # Default: the first runner in the extension, or one matching the hook name.
        def runner_class
          nil
        end

        private

        def route_by_header(headers)
          header_key = "HTTP_#{self.class.route_header_name}"
          value = headers[header_key]&.to_s
          self.class.route_mapping&.fetch(value, nil)
        end

        def route_by_field(payload)
          value = payload[self.class.route_field_name]&.to_s
          self.class.route_mapping&.fetch(value, nil)
        end

        def verify_hmac(headers, body)
          config = self.class.verify_config
          secret = resolve_secret(config[:secret])
          return true if secret.nil?

          header_key = "HTTP_#{config[:header]}"
          signature = headers[header_key]
          return false if signature.nil?

          expected = "#{config[:prefix]}#{OpenSSL::HMAC.hexdigest(config[:algorithm], secret, body)}"
          secure_compare(expected, signature)
        end

        def verify_token(headers)
          config = self.class.verify_config
          secret = resolve_secret(config[:secret])
          return true if secret.nil?

          header_key = "HTTP_#{config[:header]}"
          token = headers[header_key]&.sub(/^Bearer\s+/i, '')
          return false if token.nil?

          secure_compare(secret, token)
        end

        def resolve_secret(secret_name)
          return secret_name if secret_name.is_a?(String)

          find_setting(secret_name)
        end

        def secure_compare(left, right)
          return false if left.nil? || right.nil?
          return false if left.bytesize != right.bytesize

          left.bytes.zip(right.bytes).reduce(0) { |acc, (x, y)| acc | (x ^ y) }.zero?
        end
      end
    end
  end
end
