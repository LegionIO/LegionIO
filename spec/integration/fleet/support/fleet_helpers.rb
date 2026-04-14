# frozen_string_literal: true

require_relative 'mock_cache'
require_relative 'mock_llm'
require_relative 'mock_github'

module Fleet
  module Test
    module FleetHelpers
      # Build a standard GitHub issue work item for testing
      def build_github_issue_payload
        Fleet::Test::MockGitHub::ISSUE_PAYLOAD.dup
      end

      # Build a work item that has been through the absorber
      def build_absorbed_work_item(overrides = {})
        {
          work_item_id:    SecureRandom.uuid,
          source:          'github',
          source_ref:      'LegionIO/lex-exec#42',
          source_event:    'issues.opened',
          title:           'Fix sandbox timeout on macOS',
          description:     'The exec sandbox times out after 30s on macOS ARM64.',
          raw_payload_ref: 'fleet:payload:test-uuid',
          repo:            {
            owner:          'LegionIO',
            name:           'lex-exec',
            default_branch: 'main',
            language:       'Ruby'
          },
          config:          build_default_config,
          pipeline:        {
            stage:            'intake',
            trace:            [],
            attempt:          0,
            feedback_history: [],
            plan:             nil,
            changes:          nil,
            review_result:    nil,
            pr_number:        nil,
            branch_name:      nil,
            context_ref:      nil
          }
        }.merge(overrides)
      end

      # Build a work item that has been assessed (simple bug, skip planning)
      def build_assessed_work_item(overrides = {})
        build_absorbed_work_item.merge(
          config:   build_default_config.merge(
            priority:             :medium,
            complexity:           'simple_bug',
            estimated_difficulty: 0.3,
            planning:             { enabled: false, solvers: 1, validators: 1, max_iterations: 2 },
            validation:           build_default_config[:validation].merge(enabled: true)
          ),
          pipeline: {
            stage:            'assessed',
            trace:            [{ stage: 'assessor', node: 'test-node', started_at: Time.now.utc.iso8601 }],
            attempt:          0,
            feedback_history: [],
            plan:             nil,
            changes:          nil,
            review_result:    nil,
            pr_number:        nil,
            branch_name:      nil,
            context_ref:      nil
          }
        ).merge(overrides)
      end

      # Build a work item that has been implemented
      def build_implemented_work_item(overrides = {})
        build_assessed_work_item.merge(
          pipeline: {
            stage:            'implemented',
            trace:            [
              { stage: 'assessor', node: 'test-node', started_at: Time.now.utc.iso8601 },
              { stage: 'developer', node: 'test-node', started_at: Time.now.utc.iso8601 }
            ],
            attempt:          0,
            feedback_history: [],
            plan:             nil,
            changes:          ['lib/legion/extensions/exec/helpers/sandbox.rb', 'spec/helpers/sandbox_spec.rb'],
            review_result:    nil,
            pr_number:        100,
            branch_name:      'fleet/fix-lex-exec-42',
            context_ref:      nil
          }
        ).merge(overrides)
      end

      # Build a work item that was rejected by validator
      def build_rejected_work_item(attempt: 0, overrides: {})
        build_implemented_work_item.merge(
          pipeline: {
            stage:            'validated',
            trace:            [
              { stage: 'assessor', node: 'test-node', started_at: Time.now.utc.iso8601 },
              { stage: 'developer', node: 'test-node', started_at: Time.now.utc.iso8601 },
              { stage: 'validator', node: 'test-node', started_at: Time.now.utc.iso8601 }
            ],
            attempt:          attempt,
            feedback_history: [
              { verdict: 'rejected', issues: ['Settings.dig may return nil when key path is incomplete'],
                round: 1 }
            ],
            plan:             nil,
            changes:          ['lib/legion/extensions/exec/helpers/sandbox.rb'],
            review_result:    { verdict: 'rejected', score: 0.45, issues: [], merged_feedback: 'Add nil guard.' },
            pr_number:        100,
            branch_name:      'fleet/fix-lex-exec-42',
            context_ref:      nil
          }
        ).merge(overrides)
      end

      def build_default_config
        {
          priority:             :medium,
          complexity:           nil,
          estimated_difficulty: nil,
          planning:             { enabled: true, solvers: 1, validators: 1, max_iterations: 2 },
          implementation:       { solvers: 1, validators: 3, max_iterations: 5, models: nil },
          validation:           {
            enabled: true, run_tests: true, run_lint: true,
            security_scan: true, adversarial_review: true, reviewer_models: nil
          },
          feedback:             { drain_enabled: true, max_drain_rounds: 3, summarize_after: 2 },
          workspace:            { isolation: :worktree, cleanup_on_complete: true },
          context:              { load_repo_docs: true, load_file_tree: true, max_context_files: 50 },
          tracing:              { stage_comments: true, token_tracking: true },
          safety:               { poison_message_threshold: 2, cancel_allowed: true },
          selection:            { strategy: :test_winner },
          escalation:           { on_max_iterations: :human, consent_domain: 'fleet.shipping' }
        }
      end

      # Assert a work item has the expected pipeline stage
      def expect_stage(work_item, expected_stage)
        expect(work_item[:pipeline][:stage]).to eq(expected_stage)
      end

      # Assert a work item has a trace entry for the expected stage
      def expect_trace_includes(work_item, stage_name)
        stages = work_item[:pipeline][:trace].map { |t| t[:stage] }
        expect(stages).to include(stage_name)
      end
    end
  end
end
