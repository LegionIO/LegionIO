# frozen_string_literal: true

require_relative 'base'

module Legion
  module Trigger
    module Sources
      class Slack < Base
        source_name      'slack'
        signature_header 'HTTP_X_SLACK_SIGNATURE'
        event_header     nil
        delivery_header  'HTTP_X_SLACK_REQUEST_TIMESTAMP'

        def normalize(headers:, body:) # rubocop:disable Lint/UnusedMethodArgument
          event = dig_body(body, 'event') || {}
          {
            source:      'slack',
            event_type:  dig_body(body, 'type') || 'unknown',
            action:      dig_body(event, 'type'),
            delivery_id: dig_body(body, 'event_id'),
            payload:     body
          }
        end

        def verify_signature(headers:, body_raw:, secret:)
          timestamp = headers['HTTP_X_SLACK_REQUEST_TIMESTAMP']
          return false unless timestamp

          sig_basestring = "v0:#{timestamp}:#{body_raw}"
          digest = OpenSSL::HMAC.hexdigest('SHA256', secret, sig_basestring)
          expected = "v0=#{digest}"
          provided = headers[self.class.signature_header]
          return false unless provided

          secure_compare(provided, expected)
        end
      end
    end
  end
end
