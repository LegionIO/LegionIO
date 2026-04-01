# frozen_string_literal: true

require 'openssl'
require 'securerandom'
require_relative 'trigger/envelope'
require_relative 'trigger/sources/base'
require_relative 'trigger/sources/github'
require_relative 'trigger/sources/slack'
require_relative 'trigger/sources/linear'

module Legion
  module Trigger
    SOURCES = {
      'github' => Sources::Github,
      'slack'  => Sources::Slack,
      'linear' => Sources::Linear
    }.freeze

    class << self
      def source_for(name)
        klass = SOURCES[name.to_s]
        raise ArgumentError, "unknown trigger source: #{name} (available: #{SOURCES.keys.join(', ')})" unless klass

        klass.new
      end

      def process(source_name:, headers:, body_raw:, body:)
        adapter = source_for(source_name)
        secret = secret_for(source_name)

        verified = if secret
                     adapter.verify_signature(headers: headers, body_raw: body_raw, secret: secret)
                   else
                     false
                   end

        normalized = adapter.normalize(headers: headers, body: body)
        envelope = Envelope.new(**normalized, verified: verified)

        return { success: false, reason: :duplicate, delivery_id: envelope.delivery_id } if duplicate?(envelope)

        return { success: false, reason: :unverified } if !verified && require_verified?(source_name)

        bridge(envelope)
        mark_seen(envelope)

        { success: true, correlation_id: envelope.correlation_id, routing_key: envelope.routing_key }
      rescue ArgumentError => e
        { success: false, reason: :unknown_source, error: e.message }
      rescue StandardError => e
        Legion::Logging.error "[Trigger] process failed: #{e.message}" if defined?(Legion::Logging)
        dead_letter(source_name, body_raw, e)
        { success: false, reason: :error, error: e.message }
      end

      def registered_sources
        SOURCES.keys
      end

      private

      def bridge(envelope)
        return unless defined?(Legion::Transport::Connection) && Legion::Transport::Connection.session_open?

        channel = Legion::Transport::Connection.default_channel
        exchange = channel.topic('legion.trigger', durable: true)
        payload = defined?(Legion::JSON) ? Legion::JSON.dump(envelope.to_h) : envelope.to_h.to_json

        exchange.publish(payload, routing_key: envelope.routing_key, persistent: true,
                                 headers: { 'x-correlation-id' => envelope.correlation_id })
        Legion::Logging.info "[Trigger] bridged #{envelope.routing_key} (#{envelope.correlation_id})" if defined?(Legion::Logging)
      rescue StandardError => e
        Legion::Logging.error "[Trigger] bridge failed: #{e.message}" if defined?(Legion::Logging)
        raise
      end

      def secret_for(source_name)
        Legion::Settings.dig(:trigger, :sources, source_name.to_sym, :secret)
      rescue StandardError
        nil
      end

      def require_verified?(source_name)
        Legion::Settings.dig(:trigger, :sources, source_name.to_sym, :require_verified) != false
      rescue StandardError
        true
      end

      def duplicate?(envelope)
        return false unless envelope.delivery_id
        return false unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:get)

        Legion::Cache.get("trigger:seen:#{envelope.delivery_id}")
      rescue StandardError
        false
      end

      def mark_seen(envelope)
        return unless envelope.delivery_id
        return unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:set)

        Legion::Cache.set("trigger:seen:#{envelope.delivery_id}", '1', ttl: 86_400)
      rescue StandardError => e
        Legion::Logging.debug "[Trigger] mark_seen failed: #{e.message}" if defined?(Legion::Logging)
      end

      def dead_letter(source_name, body_raw, error)
        return unless defined?(Legion::Transport::Connection) && Legion::Transport::Connection.session_open?

        channel = Legion::Transport::Connection.default_channel
        exchange = channel.topic('legion.trigger', durable: true)
        payload = { source: source_name, body: body_raw.to_s[0..4096], error: error.message,
                    timestamp: Time.now.iso8601 }
        raw = defined?(Legion::JSON) ? Legion::JSON.dump(payload) : payload.to_json
        exchange.publish(raw, routing_key: 'trigger.dead_letter', persistent: true)
      rescue StandardError => e
        Legion::Logging.debug "[Trigger] dead_letter failed: #{e.message}" if defined?(Legion::Logging)
      end
    end
  end
end
