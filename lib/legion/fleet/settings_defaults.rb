# frozen_string_literal: true

require 'json'
require 'fileutils'

module Legion
  module Fleet
    module SettingsDefaults
      DEFAULTS = {
        fleet: {
          enabled:        true,
          sources:        [],
          llm:            {
            routing: {
              escalation: {
                enabled: true
              }
            }
          },
          planning:       {
            enabled:        true,
            solvers:        1,
            validators:     1,
            max_iterations: 2
          },
          implementation: {
            solvers:        1,
            validators:     3,
            max_iterations: 5
          },
          validation:     {
            enabled:            true,
            run_tests:          true,
            run_lint:           true,
            security_scan:      true,
            adversarial_review: true
          },
          feedback:       {
            drain_enabled:    true,
            max_drain_rounds: 3,
            summarize_after:  2
          },
          workspace:      {
            isolation:           :worktree,
            cleanup_on_complete: true
          },
          context:        {
            load_repo_docs:    true,
            load_file_tree:    true,
            max_context_files: 50
          },
          tracing:        {
            stage_comments: true,
            token_tracking: true
          },
          safety:         {
            poison_message_threshold: 2,
            cancel_allowed:           true
          },
          selection:      {
            strategy: :test_winner
          },
          escalation:     {
            on_max_iterations: :human,
            consent_domain:    'fleet.shipping'
          }
        }
      }.freeze

      def self.defaults
        DEFAULTS
      end

      def self.write_settings_file(path, force: false)
        return { success: false, reason: :exists } if File.exist?(path) && !force

        ::FileUtils.mkdir_p(File.dirname(path))
        File.write(path, ::JSON.pretty_generate(DEFAULTS))
        { success: true, path: path }
      end
    end
  end
end
