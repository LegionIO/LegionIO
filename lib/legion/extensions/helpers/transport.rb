# frozen_string_literal: true

require_relative 'base'
require 'legion/transport/helper'

module Legion
  module Extensions
    module Helpers
      module Transport
        include Legion::Extensions::Helpers::Base
        include Legion::Transport::Helper
      end
    end
  end
end
