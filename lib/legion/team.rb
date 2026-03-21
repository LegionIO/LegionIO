# frozen_string_literal: true

require 'legion/team/cost_attribution'

module Legion
  module Team
    class << self
      def current
        Legion::Settings.dig(:team, :name) || 'default'
      end

      def members
        Legion::Settings.dig(:team, :members) || []
      end

      def find(name)
        teams = Legion::Settings[:teams] || {}
        teams[name.to_sym]
      end

      def list
        (Legion::Settings[:teams] || {}).keys.map(&:to_s)
      end
    end
  end
end
