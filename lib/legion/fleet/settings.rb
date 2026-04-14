# frozen_string_literal: true

module Legion
  module Fleet
    module Settings
      FLEET_DEFAULTS = {
        enabled:                  false,
        poison_message_threshold: 2,

        transport:                {
          retry_base_delay_seconds: 1,
          retry_max_delay_seconds:  30
        },

        git:                      {
          depth: 5
        },

        workspace:                {
          base_dir:            '~/.legionio/fleet/repos',
          worktree_base:       '~/.legionio/fleet/worktrees',
          isolation:           :worktree,
          cleanup_on_complete: true,
          cleanup_clones:      false
        },

        materialization:          {
          strategy: :clone
        },

        work_item:                {
          description_max_bytes:  32_768,
          instructions_max_bytes: 16_384
        },

        cache:                    {
          dedup_ttl_seconds:    86_400,
          payload_ttl_seconds:  86_400,
          context_ttl_seconds:  86_400,
          worktree_ttl_seconds: 86_400
        },

        planning:                 {
          enabled:        true,
          solvers:        1,
          validators:     2,
          max_iterations: 5
        },

        implementation:           {
          solvers:        1,
          validators:     3,
          max_iterations: 5,
          models:         nil
        },

        validation:               {
          enabled:                true,
          run_tests:              true,
          run_lint:               true,
          security_scan:          true,
          adversarial_review:     true,
          reviewer_models:        nil,
          quality_gate_threshold: 0.8,
          quality_weights:        {
            completeness: 0.35,
            correctness:  0.35,
            quality:      0.20,
            security:     0.10
          }
        },

        feedback:                 {
          drain_enabled:    true,
          max_drain_rounds: 3,
          summarize_after:  2
        },

        context:                  {
          load_repo_docs:            true,
          load_file_tree:            true,
          max_context_files:         50,
          inline_content_max_bytes:  32_768,
          url_fetch_timeout_seconds: 30,
          url_fetch_max_bytes:       1_048_576
        },

        llm:                      {
          thinking_budget_base_tokens: 16_000,
          thinking_budget_max_tokens:  64_000,
          validator_timeout_seconds:   120
        },

        model_selection:          {
          basic_max:    0.3,
          moderate_max: 0.6
        },

        github:                   {
          pr_files_per_page: 30,
          bot_username:      nil,
          token:             nil
        },

        tracing:                  {
          stage_comments: true,
          token_tracking: true
        },

        safety:                   {
          cancel_allowed: true
        },

        selection:                {
          strategy: :test_winner
        },

        escalation:               {
          on_max_iterations: :human,
          consent_domain:    'fleet.shipping'
        }
      }.freeze

      LLM_ROUTING_OVERRIDES = {
        escalation: {
          enabled:           true,
          pipeline_enabled:  true,
          max_attempts:      3,
          quality_threshold: 50
        }
      }.freeze

      def self.apply!
        return unless defined?(Legion::Settings)

        Legion::Settings.loader.load_module_settings({ fleet: FLEET_DEFAULTS })
        Legion::Settings.loader.load_module_settings({ llm: { routing: LLM_ROUTING_OVERRIDES } })
      end
    end
  end
end
