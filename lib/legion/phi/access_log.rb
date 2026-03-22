# frozen_string_literal: true

module Legion
  module Phi
    module AccessLog
      AUDIT_EVENT_TYPE = 'phi_access'

      module_function

      # Logs PHI access to the audit trail. Returns true on success, false on failure.
      def log_access(actor:, resource:, action:, phi_fields:, reason: nil)
        entry = build_entry(actor: actor, resource: resource, action: action,
                            phi_fields: phi_fields, reason: reason)
        persist(entry)
        true
      rescue StandardError => e
        emit_warning("PHI access log failed: #{e.message}")
        false
      end

      # Same as log_access but raises on failure.
      def log_access!(actor:, resource:, action:, phi_fields:, reason: nil)
        entry = build_entry(actor: actor, resource: resource, action: action,
                            phi_fields: phi_fields, reason: reason)
        persist!(entry)
        true
      end

      # Query recent PHI access records for a given resource.
      def recent_access(resource:, limit: 100)
        if defined?(Legion::Audit)
          query_via_audit(resource: resource, limit: limit)
        else
          query_in_memory(resource: resource, limit: limit)
        end
      end

      def build_entry(actor:, resource:, action:, phi_fields:, reason:)
        {
          actor:      actor.to_s,
          resource:   resource.to_s,
          action:     action.to_s,
          phi_fields: Array(phi_fields).map(&:to_s),
          reason:     reason&.to_s,
          timestamp:  Time.now.utc.iso8601
        }
      end

      def persist(entry)
        if defined?(Legion::Audit)
          record_via_audit(entry)
        else
          log_to_logger(entry)
        end
      end

      def persist!(entry)
        if defined?(Legion::Audit)
          record_via_audit!(entry)
        else
          log_to_logger(entry)
        end
      end

      def record_via_audit(entry)
        Legion::Audit.record(
          event_type:   AUDIT_EVENT_TYPE,
          principal_id: entry[:actor],
          action:       entry[:action],
          resource:     entry[:resource],
          source:       'phi',
          detail:       format_detail(entry)
        )
      rescue StandardError => e
        emit_warning("PHI audit record failed: #{e.message}")
      end

      def record_via_audit!(entry)
        Legion::Audit.record(
          event_type:   AUDIT_EVENT_TYPE,
          principal_id: entry[:actor],
          action:       entry[:action],
          resource:     entry[:resource],
          source:       'phi',
          detail:       format_detail(entry)
        )
      end

      def log_to_logger(entry)
        return unless defined?(Legion::Logging)

        Legion::Logging.info(
          "[PHI ACCESS] actor=#{entry[:actor]} resource=#{entry[:resource]} " \
          "action=#{entry[:action]} fields=#{entry[:phi_fields].join(',')} " \
          "reason=#{entry[:reason]} at=#{entry[:timestamp]}"
        )
      end

      def emit_warning(message)
        Legion::Logging.warn(message) if defined?(Legion::Logging)
      rescue NoMethodError
        Kernel.warn(message)
      end

      def format_detail(entry)
        "fields=#{entry[:phi_fields].join(',')};reason=#{entry[:reason]}"
      end

      def query_via_audit(resource:, limit:)
        return [] unless defined?(Legion::Data::Model::AuditLog)

        Legion::Audit.recent(limit: limit, resource: resource, event_type: AUDIT_EVENT_TYPE)
      rescue StandardError => e
        Legion::Logging.warn "Phi::AccessLog#query_via_audit failed for resource=#{resource}: #{e.message}" if defined?(Legion::Logging)
        []
      end

      def query_in_memory(**)
        []
      end

      public_class_method :log_access, :log_access!, :recent_access
    end
  end
end
