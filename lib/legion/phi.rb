# frozen_string_literal: true

require 'openssl'
require 'legion/phi/access_log'
require 'legion/phi/erasure'

module Legion
  module Phi
    PHI_TAG = :phi

    DEFAULT_PHI_PATTERNS = %w[
      ssn
      social_security
      mrn
      medical_record
      dob
      date_of_birth
      patient_name
      first_name
      last_name
      full_name
      phone
      phone_number
      email
      address
      zip
      zipcode
      postal_code
      diagnosis
      icd_code
      npi
      insurance_id
      member_id
      account_number
      credit_card
      passport
      drivers_license
      ip_address
      device_id
    ].freeze

    module_function

    # Marks specific hash fields as containing PHI by adding __phi_fields metadata.
    def tag(data, fields:)
      raise ArgumentError, 'data must be a Hash' unless data.is_a?(Hash)
      raise ArgumentError, 'fields must be an Array' unless fields.is_a?(Array)

      result = data.dup
      existing = result[:__phi_fields] || []
      result[:__phi_fields] = (existing + fields.map(&:to_sym)).uniq
      result
    end

    # Returns true if the hash has a PHI tag.
    def tagged?(data)
      return false unless data.is_a?(Hash)

      data.key?(:__phi_fields) && !data[:__phi_fields].nil?
    end

    # Returns the list of PHI-tagged field names.
    def phi_fields(data)
      return [] unless tagged?(data)

      data[:__phi_fields] || []
    end

    # Returns a copy of data with all PHI fields replaced with [REDACTED].
    def redact(data)
      return data unless data.is_a?(Hash)

      fields = phi_fields(data) + auto_detect_fields(data)
      fields = fields.uniq

      result = data.dup
      fields.each do |field|
        result[field] = '[REDACTED]' if result.key?(field)
      end
      result
    end

    # Cryptographic erasure: re-encrypt PHI fields with a throwaway key, then destroy the key.
    # Returns the erased record (PHI fields replaced with erasure markers).
    def erase(data, key_id:)
      return data unless data.is_a?(Hash)

      fields = phi_fields(data) + auto_detect_fields(data)
      fields = fields.uniq

      Erasure.erase_record(record: data, phi_fields: fields, key_id: key_id)
    end

    # Auto-detect PHI fields by matching field names against configurable patterns.
    def auto_detect_fields(data)
      return [] unless data.is_a?(Hash)

      patterns = phi_patterns
      data.keys.select do |key|
        key_str = key.to_s.downcase
        patterns.any? { |pat| key_str.match?(pat) }
      end
    end

    # Returns the configured PHI field patterns (regex strings).
    def phi_patterns
      configured = settings_patterns
      return compiled_defaults if configured.nil? || configured.empty?

      configured.map { |p| Regexp.new(p, Regexp::IGNORECASE) }
    rescue StandardError => e
      Legion::Logging.warn "Phi#phi_patterns failed to compile configured patterns: #{e.message}" if defined?(Legion::Logging)
      compiled_defaults
    end

    def compiled_defaults
      DEFAULT_PHI_PATTERNS.map { |p| Regexp.new("\\b#{Regexp.escape(p)}\\b", Regexp::IGNORECASE) }
    end

    def settings_patterns
      return nil unless defined?(Legion::Settings)

      Legion::Settings.dig(:phi, :field_patterns)
    rescue StandardError => e
      Legion::Logging.debug "Phi#settings_patterns failed: #{e.message}" if defined?(Legion::Logging)
      nil
    end

    public_class_method :auto_detect_fields, :phi_patterns
  end
end
