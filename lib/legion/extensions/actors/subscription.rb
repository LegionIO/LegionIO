# frozen_string_literal: true

require_relative 'base'
require 'date'
require 'securerandom'

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
          log.log_exception(e, level: :fatal, component_type: :actor)
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

        def prepare
          @queue = queue.new
          @queue.channel.prefetch(prefetch) if defined? prefetch
          consumer_tag = "#{Legion::Settings[:client][:name]}_#{lex_name}_#{runner_name}_#{SecureRandom.uuid}"
          @consumer = Bunny::Consumer.new(@queue.channel, @queue, consumer_tag, false, false)
          @consumer.on_delivery do |delivery_info, metadata, payload|
            message = process_message(payload, metadata, delivery_info)
            fn = find_function(message)
            log.debug "[Subscription] message received: #{lex_name}/#{fn}" if defined?(log)

            affinity_result = check_region_affinity(message)
            if affinity_result == :reject
              log.warn '[Subscription] nack: region affinity mismatch'
              @queue.reject(delivery_info.delivery_tag) if manual_ack
              next
            end

            record_cross_region_metric(message) if affinity_result == :remote

            if use_runner?
              dispatch_runner(message, runner_class, fn, check_subtask?, generate_task?)
            else
              runner_class.send(fn, **message)
            end
            @queue.acknowledge(delivery_info.delivery_tag) if manual_ack

            cancel if Legion::Settings[:client][:shutting_down]
          rescue StandardError => e
            log.log_exception(e, payload_summary: "[Subscription] message processing failed: #{lex_name}/#{fn}", component_type: :actor)
            @queue.reject(delivery_info.delivery_tag) if manual_ack
          end
          log.info "[Subscription] prepared: #{lex_name}/#{runner_name}"
        rescue StandardError => e
          log.log_exception(e, level: :fatal, payload_summary: 'Subscription#prepare failed', component_type: :actor)
        end

        def activate
          unless @consumer
            log.warn "[Subscription] skipping activate for #{lex_name}/#{runner_name}: no consumer (prepare failed?)"
            return
          end
          @queue.subscribe_with(@consumer)
          log.info "[Subscription] activated: #{lex_name}/#{runner_name} (consumer registered)"
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

        def subscribe # rubocop:disable Metrics/AbcSize
          log.info "[Subscription] subscribing: #{lex_name}/#{runner_name}"
          sleep(delay_start) if delay_start.positive?
          consumer_tag = "#{Legion::Settings[:client][:name]}_#{lex_name}_#{runner_name}_#{SecureRandom.uuid}"
          on_cancellation = block { cancel }

          @consumer = @queue.subscribe(manual_ack: manual_ack, block: false, consumer_tag: consumer_tag, on_cancellation: on_cancellation) do |*rmq_message|
            payload = rmq_message.pop
            metadata = rmq_message.last
            delivery_info = rmq_message.first

            message = process_message(payload, metadata, delivery_info)
            fn = find_function(message)
            log.debug "[Subscription] message received: #{lex_name}/#{fn}" if defined?(log)

            affinity_result = check_region_affinity(message)
            if affinity_result == :reject
              log.warn "[Subscription] nack: region affinity mismatch region=#{message[:region]} affinity=#{message[:region_affinity]}"
              @queue.reject(delivery_info.delivery_tag) if manual_ack
              next
            end

            if affinity_result == :remote
              log.debug 'Processing remote-region message ' \
                        "(region=#{message[:region]}, affinity=#{message[:region_affinity]})"
              record_cross_region_metric(message)
            end

            if use_runner?
              dispatch_runner(message, runner_class, fn, check_subtask?, generate_task?)
            else
              runner_class.send(fn, **message)
            end
            @queue.acknowledge(delivery_info.delivery_tag) if manual_ack

            cancel if Legion::Settings[:client][:shutting_down]
          rescue StandardError => e
            log.log_exception(e, payload_summary: "[Subscription] message processing failed: #{lex_name}/#{fn}", component_type: :actor)
            log.warn "[Subscription] nacking message for #{lex_name}/#{fn}"
            @queue.reject(delivery_info.delivery_tag) if manual_ack
          end
          log.info "[Subscription] subscribed: #{lex_name}/#{runner_name} (consumer registered)" if defined?(log)
        end

        private

        def record_cross_region_metric(message)
          return unless defined?(Legion::Extensions::Telemetry::Runners::Telemetry)

          Legion::Extensions::Telemetry::Runners::Telemetry.record_cross_region(
            from_region: message[:region],
            to_region:   Legion::Region.current,
            affinity:    message[:region_affinity]
          )
        rescue StandardError => e
          log.debug "Subscription#record_cross_region_metric failed: #{e.message}" if defined?(log)
          nil
        end

        def check_region_affinity(message)
          return :local unless defined?(Legion::Region)

          region = message[:region]
          affinity = message[:region_affinity]
          Legion::Region.affinity_for(region, affinity)
        end

        def dispatch_runner(message, runner_cls, function, check_subtask, generate_task)
          run_block = lambda {
            Legion::Runner.run(**message,
                               runner_class:  runner_cls,
                               function:      function,
                               check_subtask: check_subtask,
                               generate_task: generate_task)
          }

          if defined?(Legion::Telemetry::OpenInference)
            Legion::Telemetry::OpenInference.chain_span(type: 'task_chain') { |_span| run_block.call }
          else
            run_block.call
          end
        end
      end
    end
  end
end
