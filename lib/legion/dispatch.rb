# frozen_string_literal: true

require_relative 'dispatch/local'

module Legion
  module Dispatch
    class << self
      def dispatcher
        @dispatcher ||= Local.new
      end

      def submit(&block)
        dispatcher.submit(&block)
      end

      def shutdown
        @dispatcher&.stop
      end

      def reset!
        @dispatcher&.stop
        @dispatcher = nil
      end
    end
  end
end
