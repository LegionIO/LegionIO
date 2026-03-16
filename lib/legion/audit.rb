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
