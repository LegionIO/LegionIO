# frozen_string_literal: true

module Legion
  module Audit
    module SiemExport
      module_function

      def export_batch(records)
        records.map do |r|
          {
            timestamp:  r[:created_at],
            source:     'legion',
            event_type: r[:event_type] || 'audit',
            principal:  r[:principal_id],
            action:     r[:action],
            resource:   r[:resource],
            status:     r[:status],
            detail:     r[:detail],
            integrity:  {
              record_hash:   r[:record_hash],
              previous_hash: r[:previous_hash],
              algorithm:     'SHA256'
            }
          }
        end
      end

      def to_ndjson(records)
        export_batch(records).map { |r| Legion::JSON.dump(r) }.join("\n")
      end
    end
  end
end
