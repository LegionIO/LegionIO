# frozen_string_literal: true

module Legion
  module Trigger
    class Envelope
      attr_reader :source, :event_type, :action, :delivery_id, :verified,
                  :correlation_id, :received_at, :payload

      def initialize(source:, event_type:, payload:, action: nil, delivery_id: nil, # rubocop:disable Metrics/ParameterLists
                     verified: false, correlation_id: nil)
        @source         = source
        @event_type     = event_type
        @action         = action
        @delivery_id    = delivery_id
        @verified       = verified
        @correlation_id = correlation_id || generate_correlation_id
        @received_at    = Time.now.iso8601
        @payload        = payload
      end

      def routing_key
        parts = ['trigger', source, event_type].compact
        parts.join('.')
      end

      def to_h
        {
          source:         source,
          event_type:     event_type,
          action:         action,
          delivery_id:    delivery_id,
          verified:       verified,
          correlation_id: correlation_id,
          received_at:    received_at,
          payload:        payload
        }
      end

      private

      def generate_correlation_id
        "leg-#{SecureRandom.hex(8)}"
      end
    end
  end
end
