# frozen_string_literal: true

require 'securerandom'

module Legion
  class API < Sinatra::Base
    module SyncDispatch
      # Dispatch a message synchronously via AMQP using a temporary reply_to queue.
      # Blocks until a response arrives or the timeout expires.
      #
      # @param exchange_name [String]   target exchange (e.g. "lex.github")
      # @param routing_key   [String]   routing key (e.g. "lex.github.runners.pull_request.create")
      # @param payload       [Hash]     message payload
      # @param envelope      [Hash]     task envelope (task_id, conversation_id, etc.)
      # @param timeout       [Integer]  seconds to wait (default 30)
      # @return [Hash]
      def self.dispatch(exchange_name, routing_key, payload, envelope, timeout: 30)
        unless defined?(Legion::Transport) &&
               Legion::Transport.respond_to?(:connected?) &&
               Legion::Transport.connected?
          return envelope.merge(
            status: 'failed',
            error:  { code: 503, message: 'Transport not available for sync dispatch' }
          )
        end

        response = nil
        reply_queue_name = "sync.reply.#{::SecureRandom.uuid}"

        begin
          channel = Legion::Transport.channel
          reply_queue = channel.queue(reply_queue_name, exclusive: true, auto_delete: true)

          reply_queue.subscribe do |_delivery_info, _metadata, body|
            response = begin
              Legion::JSON.load(body)
            rescue StandardError
              { raw: body }
            end
          end

          publish_sync(channel, exchange_name, routing_key, payload, envelope, reply_queue_name)

          deadline = Time.now + timeout
          sleep 0.05 until response || Time.now > deadline

          response || envelope.merge(
            status: 'timeout',
            error:  { code: 504, message: "Sync dispatch timed out after #{timeout}s" }
          )
        ensure
          begin
            reply_queue&.delete
          rescue StandardError
            nil
          end
        end
      rescue StandardError => e
        Legion::Logging.error "[SyncDispatch] #{e.class}: #{e.message}" if defined?(Legion::Logging)
        envelope.merge(
          status: 'failed',
          error:  { code: 500, message: e.message }
        )
      end

      # @api private
      def self.publish_sync(channel, exchange_name, routing_key, payload, envelope, reply_queue_name) # rubocop:disable Metrics/ParameterLists
        exchange = channel.exchange(exchange_name, type: :topic, durable: true, passive: true)
        message = Legion::JSON.dump(payload.merge(envelope))
        exchange.publish(
          message,
          routing_key:  routing_key,
          reply_to:     reply_queue_name,
          content_type: 'application/json',
          persistent:   false
        )
      end

      private_class_method :publish_sync
    end
  end
end
