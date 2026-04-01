# frozen_string_literal: true

module Legion
  module Trigger
    module Sources
      class Base
        class << self
          def signature_header(name = nil)
            name ? @signature_header = name : @signature_header
          end

          def event_header(name = nil)
            name ? @event_header = name : @event_header
          end

          def delivery_header(name = nil)
            name ? @delivery_header = name : @delivery_header
          end

          def source_name(name = nil)
            name ? @source_name = name : @source_name
          end
        end

        def normalize(headers:, body:)
          raise NotImplementedError, "#{self.class}#normalize must be implemented"
        end

        def verify_signature(headers:, body_raw:, secret:)
          sig_header = self.class.signature_header
          return false unless sig_header

          provided = headers[sig_header]
          return false unless provided

          expected = compute_signature(body_raw, secret)
          secure_compare(provided, expected)
        end

        private

        def dig_body(body, key)
          return nil unless body.is_a?(Hash)

          body[key] || body[key.to_sym] || body[key.to_s]
        end

        def compute_signature(body_raw, secret)
          digest = OpenSSL::HMAC.hexdigest('SHA256', secret, body_raw)
          "sha256=#{digest}"
        end

        def secure_compare(provided, expected)
          return false unless provided.bytesize == expected.bytesize

          left = provided.unpack('C*')
          right = expected.unpack('C*')
          left.zip(right).reduce(0) { |acc, (lhs, rhs)| acc | (lhs ^ rhs) }.zero?
        end
      end
    end
  end
end
