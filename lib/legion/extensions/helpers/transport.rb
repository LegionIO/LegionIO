# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Helpers
      module Transport
        include Legion::Extensions::Helpers::Base

        def transport_path
          @transport_path ||= "#{full_path}/transport"
        end

        def transport_class
          @transport_class ||= lex_class::Transport
        end

        def messages
          @messages ||= transport_class::Messages
        end

        def queues
          @queues ||= transport_class::Queues
        end

        def exchanges
          @exchanges ||= transport_class::Exchanges
        end

        def default_exchange
          @default_exchange ||= build_default_exchange
        end

        def build_default_exchange
          exchange = "#{transport_class}::Exchanges::#{lex_const}"
          return Object.const_get(exchange) if transport_class::Exchanges.const_defined? lex_const

          transport_class::Exchanges.const_set(lex_const, Class.new(Legion::Transport::Exchange))
          @default_exchange = Kernel.const_get(exchange)
          @default_exchange
        end
      end
    end
  end
end
