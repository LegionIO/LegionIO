# frozen_string_literal: true

# Mock GitHub API responses for integration testing.
# Provides canned responses for all GitHub runner methods used by the fleet.
module Fleet
  module Test
    module MockGitHub
      ISSUE_PAYLOAD = {
        'action'     => 'opened',
        'issue'      => {
          'number'   => 42,
          'title'    => 'Fix sandbox timeout on macOS',
          'body'     => 'The exec sandbox times out after 30s on macOS ARM64. ' \
                        'Need to increase the default and make it configurable.',
          'labels'   => [{ 'name' => 'bug' }],
          'user'     => { 'login' => 'matt-iverson', 'type' => 'User' },
          'html_url' => 'https://github.com/LegionIO/lex-exec/issues/42'
        },
        'repository' => {
          'full_name'      => 'LegionIO/lex-exec',
          'name'           => 'lex-exec',
          'owner'          => { 'login' => 'LegionIO' },
          'default_branch' => 'main',
          'language'       => 'Ruby',
          'clone_url'      => 'https://github.com/LegionIO/lex-exec.git'
        },
        'sender'     => { 'login' => 'matt-iverson', 'type' => 'User' }
      }.freeze

      PR_RESPONSE = {
        'number'   => 100,
        'title'    => 'fleet/fix-lex-exec-42: Fix sandbox timeout on macOS',
        'html_url' => 'https://github.com/LegionIO/lex-exec/pull/100',
        'state'    => 'open',
        'draft'    => true,
        'id'       => 999
      }.freeze

      PR_FILES = [
        { 'filename' => 'lib/legion/extensions/exec/helpers/sandbox.rb',
          'status' => 'modified', 'additions' => 5, 'deletions' => 2, 'patch' => '+timeout = 120' },
        { 'filename' => 'spec/helpers/sandbox_spec.rb',
          'status' => 'modified', 'additions' => 8, 'deletions' => 0, 'patch' => '+it "uses default"' }
      ].freeze

      LABEL_RESPONSE = { 'id' => 1, 'name' => 'fleet:received' }.freeze

      # Build mock runner module with all GitHub methods the fleet uses
      def self.build_mock_runners
        Module.new do
          def create_pull_request(owner:, repo:, title:, head:, base:, body: nil, draft: false, **) # rubocop:disable Lint/UnusedMethodArgument,Metrics/ParameterLists
            { result: Fleet::Test::MockGitHub::PR_RESPONSE }
          end

          def update_pull_request(owner:, repo:, pull_number:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: Fleet::Test::MockGitHub::PR_RESPONSE.merge('draft' => false) }
          end

          def list_pull_request_files(owner:, repo:, pull_number:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: Fleet::Test::MockGitHub::PR_FILES }
          end

          def list_pull_request_commits(owner:, repo:, pull_number:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: [
              { 'sha' => 'abc123', 'commit' => { 'message' => 'fleet: fix sandbox timeout' } }
            ] }
          end

          def add_labels_to_issue(owner:, repo:, issue_number:, labels:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: labels.map { |l| { 'name' => l } } }
          end

          def create_issue_comment(owner:, repo:, issue_number:, body:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: { 'id' => 1, 'body' => body } }
          end

          def get_issue(owner:, repo:, issue_number:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: Fleet::Test::MockGitHub::ISSUE_PAYLOAD['issue'] }
          end

          def list_issue_comments(owner:, repo:, issue_number:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: [] }
          end

          def create_webhook(owner:, repo:, config:, events:, active:, **) # rubocop:disable Lint/UnusedMethodArgument,Metrics/ParameterLists
            { result: { 'id' => 12_345, 'active' => true, 'events' => events } }
          end

          def list_webhooks(owner:, repo:, **) # rubocop:disable Lint/UnusedMethodArgument
            { result: [] }
          end

          def create_label(owner:, repo:, name:, color:, description: nil, **) # rubocop:disable Lint/UnusedMethodArgument,Metrics/ParameterLists
            { result: { 'id' => 1, 'name' => name } }
          end
        end
      end
    end
  end
end
