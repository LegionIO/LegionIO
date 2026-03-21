# frozen_string_literal: true

module Legion
  module Team
    module CostAttribution
      def self.tag(metadata = {})
        metadata.merge(
          team: Legion::Team.current,
          user: Legion::Settings.dig(:team, :user) || ENV.fetch('USER', nil)
        )
      end
    end
  end
end
