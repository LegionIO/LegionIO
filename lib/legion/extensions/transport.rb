# frozen_string_literal: true

module Legion
  module Extensions
    module Transport
      include Legion::Extensions::Helpers::Transport
      include Legion::Extensions::Helpers::Logger

      attr_accessor :exchanges, :queues, :consumers, :messages

      def build
        @queues = []
        @exchanges = []
        @messages = []
        @consumers = []
        generate_base_modules
        require_transport_items

        build_e_to_e
        build_e_to_q(e_to_q)
        build_e_to_q(additional_e_to_q)
        auto_create_dlx_exchange
        auto_create_dlx_queue
      rescue StandardError => e
        Legion::Logging.error e.message
        Legion::Logging.error e.backtrace
      end

      def generate_base_modules
        lex_class.const_set('Transport', Module.new) unless lex_class.const_defined?('Transport')
        %w[Queues Exchanges Messages Consumers].each do |thing|
          next if transport_class.const_defined? thing

          transport_class.const_set(thing, Module.new)
        end
      end

      def require_transport_items
        { exchanges: @exchanges, queues: @queues, consumers: @consumers, messages: @messages }.each do |item, obj|
          Dir[File.expand_path("#{transport_path}/#{item}/*.rb")].each do |file|
            require file
            file_name = file.to_s.split('/').last.split('.').first
            obj.push(file_name) unless obj.include?(file_name)
          end
        end
      end

      def auto_create_exchange(exchange, default_exchange = false) # rubocop:disable Style/OptionalBooleanParameter
        if Object.const_defined? exchange
          Legion::Logging.warn "#{exchange} is already defined"
          return
        end
        return build_default_exchange if default_exchange

        transport_class::Exchanges.const_set(exchange.split('::').pop, Class.new(Legion::Transport::Exchange) do
          def exchange_name
            self.class.ancestors.first.to_s.split('::')[5].downcase
          end
        end)
      end

      def auto_create_queue(queue)
        if Kernel.const_defined?(queue)
          Legion::Logging.warn "#{queue} is already defined"
          return
        end

        transport_class::Queues.const_set(queue.split('::').last, Class.new(Legion::Transport::Queue))
      end

      def auto_create_dlx_exchange
        dlx = if transport_class::Exchanges.const_defined? 'Dlx'
                transport_class::Exchanges::Dlx
              else
                transport_class::Exchanges.const_set('Dlx', Class.new(default_exchange) do
                  def exchange_name
                    "#{super}.dlx"
                  end

                  def default_type
                    'fanout'
                  end
                end)
              end

        dlx.new
      end

      def auto_create_dlx_queue
        return if transport_class::Queues.const_defined?('Dlx')

        special_name = default_exchange.new.exchange_name
        dlx_queue = Legion::Transport::Queue.new "#{special_name}.dlx", auto_delete: false
        dlx_queue.bind("#{special_name}.dlx", { routing_key: '#' })
      end

      def build_e_to_q(array)
        array.each do |binding|
          binding[:routing_key] = nil unless binding.key? :routing_key
          binding[:to] = nil unless binding.key?(:to)
          binding[:from] = default_exchange if !binding.key?(:from) || binding[:from].nil?
          bind_e_to_q(**binding)
        end
      end

      def bind_e_to_q(to:, from: default_exchange, routing_key: nil, **)
        if from.is_a? String
          from = "#{transport_class}::Exchanges::#{from.split('_').collect(&:capitalize).join}" unless from.include?('::')
          auto_create_exchange(from) unless Object.const_defined? from
        end

        if to.is_a? String
          to = "#{transport_class}::Queues::#{to.split('_').collect(&:capitalize).join}" unless to.include?('::')
          auto_create_queue(to) unless Object.const_defined?(to)
        end

        routing_key = to.to_s.split('::').last.downcase if routing_key.nil?
        bind(from, to, routing_key: routing_key)
      end

      def build_e_to_e
        e_to_e.each do |binding|
          if binding[:from].is_a? String
            binding[:from] = "#{transport_class}::Exchanges::#{binding[:from].capitalize}" unless binding[:from].include?('::')
            auto_create_exchange(binding[:from]) unless Object.const_defined? binding[:from]
          end

          if binding[:to].is_a? String
            binding[:to] = "#{transport_class}::Exchanges::#{binding[:to].capitalize}" unless binding[:to].include?('::')
            auto_create_exchange(binding[:to]) unless Object.const_defined? binding[:to]
          end

          bind(binding[:from], binding[:to], binding)
        end
      end

      def bind(from, to, routing_key: nil, **_options)
        from = from.is_a?(String) ? Kernel.const_get(from).new : from.new
        to = to.is_a?(String) ? Kernel.const_get(to).new : to.new
        to.bind(from, routing_key: routing_key)
      rescue StandardError => e
        log.fatal e.message
        log.fatal e.backtrace
        log.fatal({ from: from, to: to, routing_key: routing_key })
      end

      def e_to_q
        return [] if @exchanges.count != 1

        @queues.map do |queue|
          { from: @exchanges.first, to: queue, routing_key: queue }
        end
      end

      def e_to_e
        []
      end

      def additional_e_to_q
        []
      end
    end
  end
end
