# frozen_string_literal: true

require 'openssl'

module Legion
  module Audit
    module HashChain
      ALGORITHM = 'SHA256'
      GENESIS_HASH = ('0' * 64).freeze
      CANONICAL_FIELDS = %i[seq principal_id action resource source status detail created_at previous_hash].freeze

      module_function

      def compute_hash(record)
        payload = canonical_payload(record)
        OpenSSL::Digest.new(ALGORITHM).hexdigest(payload)
      end

      def canonical_payload(record)
        CANONICAL_FIELDS.map { |f| "#{f}:#{record[f]}" }.join('|')
      end

      def verify_chain(records)
        broken = []
        records.each_cons(2) do |prev, curr|
          unless curr[:previous_hash] == prev[:record_hash]
            broken << { id: curr[:id], type: :broken_link, expected: prev[:record_hash], got: curr[:previous_hash] }
          end
          broken << { id: curr[:id], type: :gap, expected_seq: prev[:seq] + 1, got_seq: curr[:seq] } if prev[:seq] && curr[:seq] && curr[:seq] != prev[:seq] + 1
        end
        { valid: broken.empty?, broken_links: broken, records_checked: records.size }
      end
    end
  end
end
