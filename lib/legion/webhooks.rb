# frozen_string_literal: true

require 'openssl'
require 'net/http'
require 'uri'
require 'legion/logging/helper'

module Legion
  module Webhooks
    DISPATCH_CACHE_TTL = 5

    class << self
      include Legion::Logging::Helper

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
        invalidate_dispatch_cache!
        { registered: true, id: id }
      end

      def unregister(id:, **)
        return { error: 'data_unavailable' } unless db_available?

        Legion::Data.connection[:webhooks].where(id: id).delete
        invalidate_dispatch_cache!
        { unregistered: true }
      end

      def list(**)
        return [] unless db_available?

        Legion::Data.connection[:webhooks].where(status: 'active').all
      end

      def dispatch(event_name, payload)
        return unless db_available?

        webhooks = active_dispatch_webhooks
        webhooks.each do |wh|
          patterns = event_patterns_for(wh, event_name: event_name)
          next unless patterns.any? { |p| File.fnmatch?(p, event_name) }

          log.debug { "[Webhooks] dispatching event=#{event_name} webhook_id=#{wh[:id]} patterns=#{patterns.size}" }
          deliver(wh, event_name, payload)
        end
      end

      def deliver(webhook, event_name, payload, attempt: 1)
        log.info "[Webhooks] delivery attempt #{attempt} for event=#{event_name} url=#{webhook[:url]}"
        body = delivery_body(event_name, payload)
        signature = compute_signature(webhook[:secret], body)

        response = perform_delivery_request(webhook[:url], event_name, body, signature)
        success = response.code.to_i < 400

        if success
          log.info "[Webhooks] delivered event=#{event_name} status=#{response.code}"
        else
          log.warn "[Webhooks] delivery failed event=#{event_name} status=#{response.code} url=#{webhook[:url]}"
        end

        handle_delivery_response(
          webhook:    webhook,
          event_name: event_name,
          payload:    payload,
          response:   response,
          success:    success,
          attempt:    attempt
        )
      rescue StandardError => e
        handle_exception(
          e,
          level:      :error,
          operation:  'webhooks.deliver',
          event_name: event_name,
          webhook_id: webhook[:id],
          attempt:    attempt,
          url:        webhook[:url]
        )
        handle_delivery_exception(webhook, event_name, payload, attempt, e)
      end

      def compute_signature(secret, body)
        OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      end

      private

      def invalidate_dispatch_cache!
        @active_webhooks_cache = nil
        @active_webhooks_cached_at = nil
        @pattern_cache = {}
      end

      def active_dispatch_webhooks
        cache_valid = @active_webhooks_cache && @active_webhooks_cached_at &&
                      (monotonic_now - @active_webhooks_cached_at) < DISPATCH_CACHE_TTL
        return @active_webhooks_cache if cache_valid

        @active_webhooks_cache = Legion::Data.connection[:webhooks].where(status: 'active').all
        @active_webhooks_cached_at = monotonic_now
        @active_webhooks_cache
      end

      def monotonic_now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end

      def event_patterns_for(webhook, event_name:)
        @pattern_cache ||= {}
        cache_key = [webhook[:id], webhook[:updated_at], webhook[:event_types]]
        return @pattern_cache[cache_key] if @pattern_cache.key?(cache_key)

        patterns = parse_event_patterns(webhook[:event_types], webhook_id: webhook[:id], event_name: event_name)
        @pattern_cache[cache_key] = patterns
      end

      def parse_event_patterns(raw_event_types, webhook_id:, event_name:)
        parsed = Legion::JSON.load(raw_event_types)
        Array(parsed).map(&:to_s).reject(&:empty?).then { |patterns| patterns.empty? ? ['*'] : patterns }
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'webhooks.dispatch.parse_event_types',
                            event_name: event_name, webhook_id: webhook_id)
        ['*']
      end

      def delivery_body(event_name, payload)
        Legion::JSON.dump({ event: event_name, payload: payload, timestamp: Time.now.utc.iso8601 })
      end

      def perform_delivery_request(url, event_name, body, signature)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['X-Legion-Signature'] = "sha256=#{signature}"
        request['X-Legion-Event'] = event_name
        request.body = body
        http.request(request)
      end

      def handle_delivery_response(delivery)
        error_message = "http_status=#{delivery[:response].code}" unless delivery[:success]
        record_delivery(
          webhook_id: delivery[:webhook][:id],
          event_name: delivery[:event_name],
          status:     delivery[:response].code.to_i,
          success:    delivery[:success],
          error:      error_message,
          attempt:    delivery[:attempt]
        )
        return { delivered: true, status: delivery[:response].code.to_i } if delivery[:success]

        finalize_failure(
          webhook:         delivery[:webhook],
          event_name:      delivery[:event_name],
          payload:         delivery[:payload],
          attempt:         delivery[:attempt],
          error:           error_message,
          response_status: delivery[:response].code.to_i
        )
      end

      def handle_delivery_exception(webhook, event_name, payload, attempt, error)
        record_delivery(
          webhook_id: webhook[:id],
          event_name: event_name,
          status:     nil,
          success:    false,
          error:      error.message,
          attempt:    attempt
        )
        finalize_failure(
          webhook:    webhook,
          event_name: event_name,
          payload:    payload,
          attempt:    attempt,
          error:      error.message
        )
      end

      def finalize_failure(failure)
        if retry_pending?(failure[:webhook], failure[:attempt])
          next_attempt = failure[:attempt] + 1
          log.warn "[Webhooks] retrying event=#{failure[:event_name]} next_attempt=#{next_attempt}"
          return deliver(failure[:webhook], failure[:event_name], failure[:payload], attempt: next_attempt)
        end

        dead_letter(failure[:webhook][:id], failure[:event_name], failure[:payload], failure[:attempt], failure[:error])
        { delivered: false, error: failure[:error], dead_lettered: true, status: failure[:response_status] }
      end

      def retry_pending?(webhook, attempt)
        attempt <= retry_limit(webhook)
      end

      def retry_limit(webhook)
        retries = webhook[:max_retries].to_i
        retries.negative? ? 0 : retries
      end

      def db_available?
        defined?(Legion::Data) && Legion::Data.respond_to?(:connection) && Legion::Data.connection
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'webhooks.db_available?')
        false
      end

      def record_delivery(delivery)
        Legion::Data.connection[:webhook_deliveries].insert(
          webhook_id:      delivery[:webhook_id],
          event_name:      delivery[:event_name],
          response_status: delivery[:status],
          success:         delivery[:success],
          attempt:         delivery.fetch(:attempt, 1),
          error:           delivery[:error],
          delivered_at:    Time.now.utc
        )
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'webhooks.record_delivery',
                            webhook_id: delivery[:webhook_id], event_name: delivery[:event_name],
                            status: delivery[:status], success: delivery[:success], attempt: delivery.fetch(:attempt, 1))
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
        handle_exception(e, level: :debug, operation: 'webhooks.dead_letter',
                            webhook_id: webhook_id, event_name: event_name, attempts: attempts)
        nil
      end
    end
  end
end
