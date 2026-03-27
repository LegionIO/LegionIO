# frozen_string_literal: true

require 'legion/compliance/phi_tag'
require 'legion/compliance/phi_access_log'
require 'legion/compliance/phi_erasure'

module Legion
  module Compliance
    DEFAULTS = {
      enabled:              true,
      classification_level: 'confidential',
      phi_enabled:          true,
      pci_enabled:          true,
      pii_enabled:          true,
      fedramp_enabled:      true,
      log_redaction:        true,
      cache_phi_max_ttl:    3600
    }.freeze

    class << self
      def setup
        return unless defined?(Legion::Settings)

        Legion::Settings.merge_settings(:compliance, DEFAULTS)
        Legion::Logging.info('[Compliance] max-classification profile active') if defined?(Legion::Logging)
      end

      def enabled?
        setting(:enabled) == true
      end

      def phi_enabled?
        setting(:phi_enabled) == true
      end

      def pci_enabled?
        setting(:pci_enabled) == true
      end

      def pii_enabled?
        setting(:pii_enabled) == true
      end

      def fedramp_enabled?
        setting(:fedramp_enabled) == true
      end

      def classification_level
        setting(:classification_level) || 'confidential'
      end

      def profile
        {
          classification_level: classification_level,
          phi:                  phi_enabled?,
          pci:                  pci_enabled?,
          pii:                  pii_enabled?,
          fedramp:              fedramp_enabled?,
          log_redaction:        setting(:log_redaction) == true,
          cache_phi_max_ttl:    setting(:cache_phi_max_ttl) || 3600
        }
      end

      private

      def setting(key)
        return nil unless defined?(Legion::Settings)

        Legion::Settings.dig(:compliance, key)
      rescue StandardError
        nil
      end
    end
  end
end
