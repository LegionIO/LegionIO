# frozen_string_literal: true

module Legion
  module DigitalWorker
    module Lifecycle
      TRANSITIONS = {
        'bootstrap'  => %w[active terminated],
        'active'     => %w[paused retired terminated],
        'paused'     => %w[active retired terminated],
        'retired'    => %w[terminated],
        'terminated' => []
      }.freeze

      GOVERNANCE_REQUIRED = {
        %w[retired terminated] => :council_approval,
        %w[active terminated]  => :council_approval
      }.freeze

      AUTHORITY_REQUIRED = {
        %w[active paused]  => :owner_or_manager,
        %w[paused active]  => :owner_or_manager,
        %w[active retired] => :owner_or_manager
      }.freeze

      # Map lifecycle states to lex-extinction containment levels
      EXTINCTION_MAPPING = {
        'active'     => 0, # no containment
        'paused'     => 2, # capability restriction
        'retired'    => 3, # supervised-only
        'terminated' => 4  # full termination (irreversible in lex-extinction)
      }.freeze

      # Map lifecycle states to lex-consent tiers
      CONSENT_MAPPING = {
        'bootstrap'  => :consult,    # most restrictive during bootstrap
        'active'     => :autonomous, # earned autonomy
        'paused'     => :consult,    # back to restrictive
        'retired'    => :inform,     # notification only
        'terminated' => :inform
      }.freeze

      class InvalidTransition  < StandardError; end
      class GovernanceRequired < StandardError; end
      class AuthorityRequired  < StandardError; end

      def self.transition!(worker, to_state:, by:, reason: nil, **opts)
        from_state = worker.lifecycle_state
        allowed    = TRANSITIONS.fetch(from_state, [])

        raise InvalidTransition, "cannot transition from #{from_state} to #{to_state}" unless allowed.include?(to_state)

        if governance_required?(from_state, to_state)
          required = GOVERNANCE_REQUIRED[[from_state, to_state]]
          raise GovernanceRequired, "#{from_state} -> #{to_state} requires #{required}" unless opts[:governance_override] == true
        end

        authority = authority_type(from_state, to_state)
        raise AuthorityRequired, "#{from_state} -> #{to_state} requires #{authority} (by: #{by})" if authority && opts[:authority_verified] != true

        worker.update(
          lifecycle_state: to_state,
          updated_at:      Time.now.utc,
          retired_at:      %w[retired terminated].include?(to_state) ? Time.now.utc : worker.retired_at,
          retired_by:      %w[retired terminated].include?(to_state) ? by : worker.retired_by,
          retired_reason:  reason || worker.retired_reason
        )

        if defined?(Legion::Events)
          Legion::Events.emit('worker.lifecycle', {
                                worker_id:        worker.worker_id,
                                from_state:       from_state,
                                to_state:         to_state,
                                by:               by,
                                reason:           reason,
                                extinction_level: extinction_level(to_state),
                                consent_tier:     consent_tier(to_state),
                                at:               Time.now.utc
                              })
        end

        if defined?(Legion::Audit)
          begin
            Legion::Audit.record(
              event_type:     'lifecycle_transition',
              principal_id:   by,
              principal_type: 'human',
              action:         'transition',
              resource:       worker.worker_id,
              source:         'system',
              status:         'success',
              detail:         { from_state: from_state, to_state: to_state, reason: reason }
            )
          rescue StandardError => e
            Legion::Logging.debug("Audit in lifecycle.transition! failed: #{e.message}") if defined?(Legion::Logging)
          end
        end

        worker
      end

      def self.valid_transition?(from_state, to_state)
        TRANSITIONS.fetch(from_state, []).include?(to_state)
      end

      def self.governance_required?(from_state, to_state)
        GOVERNANCE_REQUIRED.key?([from_state, to_state])
      end

      def self.authority_type(from_state, to_state)
        AUTHORITY_REQUIRED[[from_state, to_state]]
      end

      def self.extinction_level(state)
        EXTINCTION_MAPPING.fetch(state, 0)
      end

      def self.consent_tier(state)
        CONSENT_MAPPING.fetch(state, :consult)
      end
    end
  end
end
