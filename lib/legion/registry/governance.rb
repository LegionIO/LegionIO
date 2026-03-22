# frozen_string_literal: true

module Legion
  module Registry
    module Governance
      DEFAULTS = {
        require_airb_approval:      false,
        auto_approve_risk_tiers:    %w[low],
        review_required_risk_tiers: %w[medium high critical],
        naming_convention:          'lex-[a-z][a-z0-9_]*',
        deprecation_notice_days:    30
      }.freeze

      class << self
        def config
          @config ||= load_config
        end

        def check_name(name)
          pattern = Regexp.new("\\A#{config[:naming_convention]}\\z")
          pattern.match?(name.to_s)
        end

        def auto_approve?(risk_tier)
          config[:auto_approve_risk_tiers].include?(risk_tier.to_s)
        end

        def review_required?(risk_tier)
          config[:review_required_risk_tiers].include?(risk_tier.to_s)
        end

        def reset!
          @config = nil
        end

        private

        def load_config
          return DEFAULTS unless defined?(Legion::Settings)

          overrides = Legion::Settings.dig(:registry, :governance)
          return DEFAULTS.merge(overrides) if overrides.is_a?(Hash)

          DEFAULTS
        rescue StandardError
          DEFAULTS
        end
      end
    end
  end
end
