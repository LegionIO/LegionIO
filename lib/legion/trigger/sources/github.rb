# frozen_string_literal: true

require_relative 'base'

module Legion
  module Trigger
    module Sources
      class Github < Base
        source_name      'github'
        signature_header 'HTTP_X_HUB_SIGNATURE_256'
        event_header     'HTTP_X_GITHUB_EVENT'
        delivery_header  'HTTP_X_GITHUB_DELIVERY'

        def normalize(headers:, body:)
          {
            source:      'github',
            event_type:  headers[self.class.event_header],
            action:      dig_body(body, 'action'),
            delivery_id: headers[self.class.delivery_header],
            payload:     body
          }
        end
      end
    end
  end
end
