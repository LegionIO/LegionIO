# frozen_string_literal: true

module Legion
  module Audit
    class << self
      def record(event_type:, principal_id:, action:, resource:, **opts)
        return unless transport_available?

        Legion::Extensions::Audit::Transport::Messages::Audit.new(
          event_type:     event_type,
          principal_id:   principal_id,
          principal_type: opts[:principal_type] || 'system',
          action:         action,
          resource:       resource,
          source:         opts[:source] || 'unknown',
          node:           node_name,
          status:         opts[:status] || 'success',
          duration_ms:    opts[:duration_ms],
          detail:         opts[:detail],
          created_at:     Time.now.utc.iso8601
        ).publish
      rescue StandardError => e
        Legion::Logging.debug "Audit publish failed: #{e.message}" if defined?(Legion::Logging)
      end

      def recent_for(principal_id:, window: 3600, event_type: nil, status: nil)
        return [] unless defined?(Legion::Data::Model::AuditLog)

        ds = Legion::Data::Model::AuditLog
             .where(principal_id: principal_id)
             .where { created_at >= Time.now.utc - window }
        ds = ds.where(event_type: event_type) unless event_type.nil?
        ds = ds.where(status: status) unless status.nil?
        ds.all
      end

      def count_for(principal_id:, window: 3600, event_type: nil, status: nil)
        return 0 unless defined?(Legion::Data::Model::AuditLog)

        ds = Legion::Data::Model::AuditLog
             .where(principal_id: principal_id)
             .where { created_at >= Time.now.utc - window }
        ds = ds.where(event_type: event_type) unless event_type.nil?
        ds = ds.where(status: status) unless status.nil?
        ds.count
      end

      def failure_count_for(principal_id:, window: 3600)
        count_for(principal_id: principal_id, window: window, status: 'failure')
      end

      def success_count_for(principal_id:, window: 3600)
        count_for(principal_id: principal_id, window: window, status: 'success')
      end

      def resources_for(principal_id:, window: 3600)
        return [] unless defined?(Legion::Data::Model::AuditLog)

        Legion::Data::Model::AuditLog
          .where(principal_id: principal_id)
          .where { created_at >= Time.now.utc - window }
          .select_map(:resource)
          .uniq
      end

      def recent(limit: 50, **filters)
        return [] unless defined?(Legion::Data::Model::AuditLog)

        ds = Legion::Data::Model::AuditLog.order(Sequel.desc(:created_at)).limit(limit)
        filters.each { |col, val| ds = ds.where(col => val) }
        ds.all
      end

      private

      def transport_available?
        defined?(Legion::Transport) &&
          Legion::Settings[:transport][:connected] == true &&
          defined?(Legion::Extensions::Audit::Transport::Messages::Audit)
      end

      def node_name
        Legion::Settings[:client][:hostname]
      rescue StandardError
        'unknown'
      end
    end
  end
end
