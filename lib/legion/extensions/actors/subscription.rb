# frozen_string_literal: true

require_relative 'base'
require 'date'

module Legion
  module Extensions
    module Actors
      class Subscription
        include Concurrent::Async
        include Legion::Extensions::Actors::Base
        include Legion::Extensions::Helpers::Transport

        def initialize(**_options)
          super()
          @queue = queue.new
          @queue.channel.prefetch(prefetch) if defined? prefetch
        rescue StandardError => e
          log.fatal e.message
          log.fatal e.backtrace
        end

        def create_queue
          queues.const_set(actor_const, Class.new(Legion::Transport::Queue))
          exchange_object = default_exchange.new
          queue_object = Kernel.const_get(queue_string).new

          queue_object.bind(exchange_object, routing_key: actor_name)
          queue_object.bind(exchange_object, routing_key: "#{lex_name}.#{actor_name}.#")
        end

        def queue
          create_queue unless queues.const_defined?(actor_const, false)
          queues.const_get(actor_const, false)
        end

        def queue_string
          @queue_string ||= "#{queues}::#{actor_const}"
        end

        def cancel
          return true unless @queue.channel.active

          log.debug "Closing subscription to #{@queue.name}"
          @consumer.cancel
          @queue.channel.close
          true
        end

        def block
          false
        end

        def consumers
          1
        end

        def manual_ack
          true
        end

        def delay_start
          0
        end

        def include_metadata_in_message?
          true
        end

        def process_message(message, metadata, delivery_info)
          payload = if metadata.content_encoding && metadata.content_encoding == 'encrypted/cs'
                      Legion::Crypt.decrypt(message, metadata.headers['iv'])
                    elsif metadata.content_encoding && metadata.content_encoding == 'encrypted/pk'
                      Legion::Crypt.decrypt_from_keypair(metadata.headers[:public_key], message)
                    else
                      message
                    end

          message = if metadata.content_type == 'application/json'
                      Legion::JSON.load(payload)
                    else
                      { value: payload }
                    end
          if include_metadata_in_message?
            message = message.merge(metadata.headers.transform_keys(&:to_sym)) unless metadata.headers.nil?
            message[:routing_key] = delivery_info[:routing_key]
          end

          message[:timestamp] = (message[:timestamp_in_ms] / 1000).round if message.key?(:timestamp_in_ms) && !message.key?(:timestamp)
          message[:datetime] = Time.at(message[:timestamp].to_i).to_datetime.to_s if message.key?(:timestamp)
          message
        end

        def find_function(message = {})
          return runner_function if actor_class.method_defined?(:runner_function, false)
          return function if actor_class.method_defined?(:function, false)
          return action if actor_class.method_defined?(:action, false)
          return message[:function] if message.key? :function

          function
        end

        def subscribe
          sleep(delay_start) if delay_start.positive?
          consumer_tag = "#{Legion::Settings[:client][:name]}_#{lex_name}_#{runner_name}_#{Thread.current.object_id}"
          on_cancellation = block { cancel }

          @consumer = @queue.subscribe(manual_ack: manual_ack, block: false, consumer_tag: consumer_tag, on_cancellation: on_cancellation) do |*rmq_message|
            payload = rmq_message.pop
            metadata = rmq_message.last
            delivery_info = rmq_message.first

            message = process_message(payload, metadata, delivery_info)
            if use_runner?
              Legion::Runner.run(**message,
                                 runner_class:  runner_class,
                                 function:      find_function(message),
                                 check_subtask: check_subtask?,
                                 generate_task: generate_task?)
            else
              runner_class.send(find_function(message), **message)
            end
            @queue.acknowledge(delivery_info.delivery_tag) if manual_ack

            cancel if Legion::Settings[:client][:shutting_down]
          rescue StandardError => e
            Legion::Logging.error e.message
            Legion::Logging.error e.backtrace
            Legion::Logging.error message
            Legion::Logging.error function
            @queue.reject(delivery_info.delivery_tag) if manual_ack
          end
        end
      end
    end
  end
end
