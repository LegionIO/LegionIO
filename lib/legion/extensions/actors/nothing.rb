# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Actors
      class Nothing
        include Legion::Extensions::Actors::Base

        def cancel(**)
          request_stop
        end
      end
    end
  end
end
