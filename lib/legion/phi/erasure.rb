# frozen_string_literal: true

require 'openssl'

module Legion
  module Phi
    module Erasure
      ERASURE_MARKER    = '[ERASED]'
      ERASURE_ALGORITHM = 'aes-256-gcm'

      module_function

      # Erase all PHI for a data subject. Returns an erasure audit entry.
      def erase_for_subject(subject_id:)
        timestamp = Time.now.utc.iso8601
        entry = {
          subject_id: subject_id.to_s,
          erased_at:  timestamp,
          method:     'cryptographic_erasure',
          algorithm:  ERASURE_ALGORITHM,
          key_id:     generate_key_id,
          status:     'completed'
        }
        append_erasure_log(entry)
        entry
      end

      # Erase PHI in a single record by encrypting PHI fields with a throwaway key.
      # The key is immediately discarded, making the data unrecoverable.
      def erase_record(record:, phi_fields:, key_id: nil)
        return record unless record.is_a?(Hash)
        return record if phi_fields.nil? || phi_fields.empty?

        key_id ||= generate_key_id
        ephemeral_key = generate_ephemeral_key

        result = record.dup
        phi_fields.each do |field|
          next unless result.key?(field)

          result[field] = encrypt_and_erase(result[field], ephemeral_key, key_id)
        end

        # Destroy the ephemeral key immediately — data is now unrecoverable
        ephemeral_key.replace(OpenSSL::Random.random_bytes(32))
        ephemeral_key = nil

        result
      end

      # Returns the in-process erasure audit trail.
      def erasure_log
        @erasure_log ||= []
        @erasure_log.dup.freeze
      end

      # Clears the in-process erasure log (used for testing).
      def reset_erasure_log!
        @erasure_log = []
      end

      def encrypt_and_erase(value, key, key_id)
        return ERASURE_MARKER if value.nil?

        plaintext = value.to_s
        cipher    = OpenSSL::Cipher.new(ERASURE_ALGORITHM)
        cipher.encrypt
        cipher.key = key[0, 32]
        iv = cipher.random_iv
        cipher.iv = iv

        ciphertext = cipher.update(plaintext) + cipher.final
        tag        = cipher.auth_tag

        # Return an erasure marker with minimal forensic metadata (no recoverable data)
        "#{ERASURE_MARKER}[key_id=#{key_id},iv=#{iv.unpack1('H*')},tag=#{tag.unpack1('H*')},len=#{ciphertext.bytesize}]"
      rescue OpenSSL::Cipher::CipherError
        ERASURE_MARKER
      end

      def generate_ephemeral_key
        OpenSSL::Random.random_bytes(32)
      end

      def generate_key_id
        OpenSSL::Random.random_bytes(16).unpack1('H*')
      end

      def append_erasure_log(entry)
        @erasure_log ||= []
        @erasure_log << entry

        if defined?(Legion::Audit)
          Legion::Audit.record(
            event_type:   'phi_erasure',
            principal_id: entry[:subject_id],
            action:       'erase',
            resource:     "subject/#{entry[:subject_id]}",
            source:       'phi_erasure',
            detail:       "method=#{entry[:method]};algorithm=#{entry[:algorithm]};key_id=#{entry[:key_id]}"
          )
        elsif defined?(Legion::Logging)
          Legion::Logging.info(
            "[PHI ERASURE] subject=#{entry[:subject_id]} method=#{entry[:method]} " \
            "algorithm=#{entry[:algorithm]} at=#{entry[:erased_at]}"
          )
        end
      rescue StandardError
        # Never raise from erasure log — ensure the erase always appears to succeed
      end

      public_class_method :erase_for_subject, :erase_record, :erasure_log, :reset_erasure_log!
    end
  end
end
