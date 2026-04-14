# frozen_string_literal: true

# Mock LLM responses keyed by fleet stage.
# Each stage returns a canned response matching the expected schema.
# All mocks use Legion::LLM::Prompt (dispatch/extract/summarize), NOT Legion::LLM.chat.
module Fleet
  module Test
    module MockLLM
      RESPONSES = {
        # Assessor classification response (structured output)
        assessor_classify:                {
          priority:             'medium',
          complexity:           'simple_bug',
          work_type:            'bug_fix',
          language:             'ruby',
          estimated_difficulty: 0.3
        },

        # Planner plan response (structured output)
        planner_plan:                     {
          approach:          'Fix the timeout by increasing the default value and adding a configurable parameter.',
          files_to_modify:   [
            { path: 'lib/legion/extensions/exec/helpers/sandbox.rb', action: 'modify',
              reason: 'Increase default timeout and add config parameter' },
            { path: 'spec/helpers/sandbox_spec.rb', action: 'modify',
              reason: 'Add test for configurable timeout' }
          ],
          files_to_read:     %w[lib/legion/extensions/exec/helpers/sandbox.rb README.md],
          test_strategy:     'Add RSpec examples for new timeout config',
          estimated_changes: 2
        },

        # Developer implementation response (chat)
        developer_implement:              <<~RESPONSE,
          I'll fix the sandbox timeout issue. Here are the changes:

          ```ruby
          # lib/legion/extensions/exec/helpers/sandbox.rb
          module Legion
            module Extensions
              module Exec
                module Helpers
                  module Sandbox
                    DEFAULT_TIMEOUT = 120 # increased from 30

                    def execute_with_timeout(command:, timeout: DEFAULT_TIMEOUT, **)
                      Timeout.timeout(timeout) { system(command) }
                    end
                  end
                end
              end
            end
          end
          ```

          ```ruby
          # spec/helpers/sandbox_spec.rb
          RSpec.describe Legion::Extensions::Exec::Helpers::Sandbox do
            it 'uses default timeout of 120 seconds' do
              expect(described_class::DEFAULT_TIMEOUT).to eq(120)
            end
          end
          ```
        RESPONSE

        # Developer implementation response for feedback incorporation
        developer_feedback:               <<~RESPONSE,
          I've addressed the review feedback. The timeout is now configurable via settings:

          ```ruby
          # lib/legion/extensions/exec/helpers/sandbox.rb
          DEFAULT_TIMEOUT = Legion::Settings.dig(:exec, :sandbox, :timeout) || 120
          ```
        RESPONSE

        # Validator review response: approved
        validator_approve:                {
          verdict:  'approved',
          score:    0.92,
          issues:   [],
          feedback: 'Code changes look correct. Timeout is properly configurable.'
        },

        # Validator review response: rejected
        validator_reject:                 {
          verdict:  'rejected',
          score:    0.45,
          issues:   [
            { severity: 'high', file: 'lib/legion/extensions/exec/helpers/sandbox.rb',
              description: 'Settings access without fallback could raise if settings not loaded' }
          ],
          feedback: 'Settings.dig may return nil if exec settings are not configured. Add a nil guard.'
        },

        # Validator review response: second review (approved after feedback)
        validator_approve_after_feedback: {
          verdict:  'approved',
          score:    0.88,
          issues:   [],
          feedback: 'Nil guard added. Code is correct.'
        }
      }.freeze

      def self.response_for(stage)
        RESPONSES.fetch(stage)
      end

      # Build a mock Legion::LLM::Prompt module for use with stub_const in specs.
      # Fleet extensions use Prompt.dispatch (auto-routed) and Prompt.extract
      # (structured output), NOT Legion::LLM.chat or .structured.
      # Returns the module -- callers use stub_const in their own `before` blocks:
      #   before { stub_const('Legion::LLM::Prompt', MockLLM.build_prompt_double) }
      def self.build_prompt_double
        Module.new do
          extend self

          def dispatch(message, **_opts)
            content = message.to_s
            if content.include?('feedback')
              {
                content:  Fleet::Test::MockLLM.response_for(:developer_feedback),
                model:    'claude-sonnet-4-20250514',
                provider: 'anthropic'
              }
            else
              {
                content:  Fleet::Test::MockLLM.response_for(:developer_implement),
                model:    'claude-sonnet-4-20250514',
                provider: 'anthropic'
              }
            end
          end

          def extract(message, schema:, **_opts) # rubocop:disable Lint/UnusedMethodArgument
            schema_name = schema[:name] || schema.to_s
            result = if schema_name.include?('classif')
                       Fleet::Test::MockLLM.response_for(:assessor_classify)
                     elsif schema_name.include?('plan')
                       Fleet::Test::MockLLM.response_for(:planner_plan)
                     elsif schema_name.include?('review')
                       Fleet::Test::MockLLM.response_for(:validator_approve)
                     else
                       {}
                     end
            result.merge(model: 'claude-sonnet-4-20250514', provider: 'anthropic')
          end

          def summarize(message, **_opts)
            { content: message.to_s[0..200], model: 'claude-haiku-4-20250514', provider: 'anthropic' }
          end

          def started? = true
        end
      end
    end
  end
end
