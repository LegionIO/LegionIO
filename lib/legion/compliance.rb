# frozen_string_literal: true

require 'legion/compliance/phi_tag'
require 'legion/compliance/phi_access_log'

module Legion
  module Compliance
    class << self
      def phi_enabled?
        return false unless defined?(Legion::Settings)

        Legion::Settings[:compliance][:phi_enabled] == true
      rescue StandardError
        false
      end
    end
  end
end
