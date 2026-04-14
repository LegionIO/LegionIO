# frozen_string_literal: true

module Legion
  module Fleet
    module ConditionerRules
      # Conditioner rules that complement the relationship conditions.
      # These are higher-level routing rules that the conditioner evaluates
      # when a relationship's conditions are met but additional logic is needed.
      #
      # The primary routing (which stage follows which) is handled by the
      # 10 relationships in manifest.yml. These rules provide supplementary
      # conditioning for edge cases.
      RULES = [
        {
          name:        'fleet-skip-planning-trivial',
          description: 'Skip planning for trivial fixes (assessor sets planning.enabled=false)',
          conditions:  {
            all: [
              { fact: 'results.config.complexity', operator: 'equal', value: 'trivial' },
              { fact: 'results.config.planning.enabled', operator: 'equal', value: true }
            ]
          },
          action:      :override,
          overrides:   { 'results.config.planning.enabled' => false }
        },
        {
          name:        'fleet-skip-validation-trivial',
          description: 'Skip validation for trivial fixes',
          conditions:  {
            all: [
              { fact: 'results.config.complexity', operator: 'equal', value: 'trivial' },
              { fact: 'results.config.validation.enabled', operator: 'equal', value: true }
            ]
          },
          action:      :override,
          overrides:   { 'results.config.validation.enabled' => false }
        },
        {
          name:        'fleet-escalate-max-iterations',
          description: 'Route to escalation when max iterations exceeded',
          conditions:  {
            all: [
              { fact: 'results.pipeline.review_result.verdict', operator: 'equal', value: 'rejected' },
              { fact: 'results.pipeline.attempt', operator: 'greater_or_equal', value: 4 }
            ]
          },
          action:      :route,
          target:      { extension: 'assessor', runner: 'assessor', function: 'escalate' }
        },
        {
          name:        'fleet-critical-production-max-capability',
          description: 'Critical production issues get maximum capability models',
          conditions:  {
            all: [
              { fact: 'results.config.priority', operator: 'equal', value: 'critical' }
            ]
          },
          action:      :override,
          overrides:   {
            'results.config.implementation.solvers'        => 3,
            'results.config.implementation.validators'     => 3,
            'results.config.implementation.max_iterations' => 10
          }
        },
        {
          name:          'fleet-governance-mind-growth',
          description:   'Mind growth proposals require governance approval',
          conditions:    {
            all: [
              { fact: 'results.source', operator: 'equal', value: 'mind_growth' },
              { fact: 'results.config.priority', operator: 'in_set', value: %w[high critical] }
            ]
          },
          action:        :require_approval,
          approval_type: 'fleet.governance.mind_growth'
        }
      ].freeze

      def self.rules
        RULES
      end

      def self.seed!
        return { success: false, error: :data_not_available } unless defined?(Legion::Data)

        seeded = RULES.map { |rule| rule[:name] }
        { success: true, seeded: seeded }
      end
    end
  end
end
