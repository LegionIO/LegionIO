# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Actors
      class Loop
        include Concurrent::Async
        include Legion::Extensions::Actors::Base

        def initialize
          @loop = true
          async.run
        rescue StandardError => e
          Legion::Logging.error e
          Legion::Logging.error e.backtrace
        end

        def run
          action while @loop
        end

        def action(**_opts)
          Legion::Logging.warn 'An extension is using the default action for a loop'
        end

        def cancel
          @loop = false
        end
      end
    end
  end
end
