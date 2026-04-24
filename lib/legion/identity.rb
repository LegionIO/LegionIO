# frozen_string_literal: true

require 'concurrent/array'

module Legion
  module Identity
    class << self
      attr_accessor :pending_registrations
    end
    self.pending_registrations = Concurrent::Array.new
  end
end

require_relative 'identity/trust'
require_relative 'identity/resolver'
