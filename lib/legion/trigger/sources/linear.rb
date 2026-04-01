# frozen_string_literal: true

require_relative 'base'

module Legion
  module Trigger
    module Sources
      class Linear < Base
        source_name      'linear'
        signature_header 'HTTP_LINEAR_SIGNATURE'
        event_header     'HTTP_LINEAR_EVENT'
        delivery_header  'HTTP_LINEAR_DELIVERY'

        def normalize(headers:, body:)
          {
            source:      'linear',
            event_type:  headers[self.class.event_header] || dig_body(body, 'type') || 'unknown',
            action:      dig_body(body, 'action'),
            delivery_id: headers[self.class.delivery_header],
            payload:     body
          }
        end
      end
    end
  end
end
