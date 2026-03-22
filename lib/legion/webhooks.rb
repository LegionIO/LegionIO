# frozen_string_literal: true

require 'openssl'
require 'net/http'
require 'uri'

module Legion
  module Webhooks
    class << self
      def register(url:, secret:, event_types: ['*'], max_retries: 5, **)
        return { error: 'data_unavailable' } unless db_available?

        id = Legion::Data.connection[:webhooks].insert(
          url:         url,
          secret:      secret,
          event_types: Legion::JSON.dump(event_types),
          max_retries: max_retries,
          status:      'active',
          created_at:  Time.now.utc,
          updated_at:  Time.now.utc
        )
        { registered: true, id: id }
      end

      def unregister(id:, **)
        return { error: 'data_unavailable' } unless db_available?

        Legion::Data.connection[:webhooks].where(id: id).delete
        { unregistered: true }
      end

      def list(**)
        return [] unless db_available?

        Legion::Data.connection[:webhooks].where(status: 'active').all
      end

      def dispatch(event_name, payload)
        return unless db_available?

        webhooks = Legion::Data.connection[:webhooks].where(status: 'active').all
        webhooks.each do |wh|
          patterns = begin
            Legion::JSON.load(wh[:event_types])
          rescue StandardError => e
            Legion::Logging.debug("Webhooks#dispatch event_types parse failed: #{e.message}") if defined?(Legion::Logging)
            ['*']
          end
          next unless patterns.any? { |p| File.fnmatch?(p, event_name) }

          deliver(wh, event_name, payload)
        end
      end

      def deliver(webhook, event_name, payload, attempt: 1)
        Legion::Logging.info "[Webhooks] delivery attempt #{attempt} for event=#{event_name} url=#{webhook[:url]}" if defined?(Legion::Logging)
        body = Legion::JSON.dump({ event: event_name, payload: payload, timestamp: Time.now.utc.iso8601 })
        signature = compute_signature(webhook[:secret], body)

        uri = URI.parse(webhook[:url])
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['X-Legion-Signature'] = "sha256=#{signature}"
        request['X-Legion-Event'] = event_name
        request.body = body

        response = http.request(request)
        success = response.code.to_i < 400

        if success
          Legion::Logging.info "[Webhooks] delivered event=#{event_name} status=#{response.code}" if defined?(Legion::Logging)
        elsif defined?(Legion::Logging)
          Legion::Logging.error "[Webhooks] delivery failed event=#{event_name} status=#{response.code} url=#{webhook[:url]}"
        end

        record_delivery(webhook[:id], event_name, response.code.to_i, success)
        { delivered: success, status: response.code.to_i }
      rescue StandardError => e
        Legion::Logging.error "[Webhooks] delivery error event=#{event_name}: #{e.message}" if defined?(Legion::Logging)
        record_delivery(webhook[:id], event_name, nil, false, error: e.message)
        if attempt < (webhook[:max_retries] || 5)
          Legion::Logging.warn "[Webhooks] will retry event=#{event_name} attempt=#{attempt}" if defined?(Legion::Logging)
          { delivered: false, error: e.message, will_retry: true }
        else
          dead_letter(webhook[:id], event_name, payload, attempt, e.message)
          { delivered: false, error: e.message, dead_lettered: true }
        end
      end

      def compute_signature(secret, body)
        OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      end

      private

      def db_available?
        defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
      rescue StandardError => e
        Legion::Logging.debug("Webhooks#db_available? failed: #{e.message}") if defined?(Legion::Logging)
        false
      end

      def record_delivery(webhook_id, event_name, status, success, error: nil)
        Legion::Data.connection[:webhook_deliveries].insert(
          webhook_id:      webhook_id,
          event_name:      event_name,
          response_status: status,
          success:         success,
          error:           error,
          delivered_at:    Time.now.utc
        )
      rescue StandardError => e
        Legion::Logging.debug("Webhooks#record_delivery failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      def dead_letter(webhook_id, event_name, payload, attempts, error)
        Legion::Data.connection[:webhook_dead_letters].insert(
          webhook_id: webhook_id,
          event_name: event_name,
          payload:    Legion::JSON.dump(payload),
          attempts:   attempts,
          last_error: error,
          created_at: Time.now.utc
        )
      rescue StandardError => e
        Legion::Logging.debug("Webhooks#dead_letter failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end
    end
  end
end
