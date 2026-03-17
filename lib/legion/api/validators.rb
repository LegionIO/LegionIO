# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Validators
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      def validate_required!(body, *keys)
        missing = keys.select { |k| body[k].nil? || (body[k].respond_to?(:empty?) && body[k].empty?) }
        return if missing.empty?

        halt 400, json_error('missing_fields', "required: #{missing.join(', ')}", status_code: 400)
      end

      def validate_string_length!(value, field:, max: 255)
        return unless value.is_a?(String) && value.length > max

        halt 400, json_error('field_too_long', "#{field} exceeds #{max} characters", status_code: 400)
      end

      def validate_enum!(value, field:, allowed:)
        return if value.nil?
        return if allowed.include?(value.to_s)

        halt 400, json_error('invalid_value', "#{field} must be one of: #{allowed.join(', ')}", status_code: 400)
      end

      def validate_uuid!(value, field:)
        return if value.nil?
        return if value.to_s.match?(UUID_PATTERN)

        halt 400, json_error('invalid_format', "#{field} must be a valid UUID", status_code: 400)
      end

      def validate_integer!(value, field:, min: nil, max: nil)
        return if value.nil?

        int_val = value.to_i
        halt 400, json_error('out_of_range', "#{field} must be >= #{min}", status_code: 400) if min && int_val < min
        halt 400, json_error('out_of_range', "#{field} must be <= #{max}", status_code: 400) if max && int_val > max
      end
    end
  end
end
