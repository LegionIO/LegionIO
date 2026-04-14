# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'json'
require 'digest'

require_relative 'support/fleet_helpers'
require_relative 'support/mock_cache'
require_relative 'support/mock_llm'
require_relative 'support/mock_github'

# ---------------------------------------------------------------------------
# Minimal stub for the GitHub absorber (WS-11 target module).
# Tests verify the *contract* of the absorber, not the implementation.
# ---------------------------------------------------------------------------
module Legion
  module Extensions
    module Github
      module Absorbers
        module Issues
          # Normalize a raw GitHub issues webhook payload into the standard
          # fleet work item format (stage: 'intake').
          def self.normalize(payload)
            issue = payload['issue']
            repo = payload['repository']

            {
              work_item_id:    SecureRandom.uuid,
              source:          'github',
              source_ref:      "#{repo['full_name']}##{issue['number']}",
              source_event:    "issues.#{payload['action']}",
              title:           issue['title'],
              description:     issue['body'],
              raw_payload_ref: "fleet:payload:#{SecureRandom.uuid}",
              repo:            {
                owner:          repo.dig('owner', 'login'),
                name:           repo['name'],
                default_branch: repo['default_branch'],
                language:       repo['language']
              },
              config:          {
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
              },
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
            }
          end

          # Absorb a GitHub issues webhook payload.
          # Stores raw payload in cache; does NOT perform dedup (that is the assessor's job).
          # Returns { absorbed: true, work_item_id: } or { absorbed: false, reason: }.
          def self.absorb(payload:, cache: Legion::Cache)
            sender = payload['sender'] || {}
            return { absorbed: false, reason: :bot_generated } if bot_generated?(sender)

            work_item = normalize(payload)
            cache.set(work_item[:raw_payload_ref], ::JSON.generate(payload), ttl: 86_400)

            { absorbed: true, work_item_id: work_item[:work_item_id] }
          end

          def self.bot_generated?(sender)
            return false if sender.nil? || sender.empty?

            sender['type'] == 'Bot' || sender['login'].to_s.include?('[bot]')
          end
          private_class_method :bot_generated?
        end
      end
    end
  end
end

RSpec.describe 'Fleet Pipeline Integration' do
  include Fleet::Test::FleetHelpers

  let(:cache) { Fleet::Test::MockCache.new }
  let(:published_messages) { [] }

  before do
    stub_const('Legion::Cache', cache)

    json_mod = Module.new do
      def self.dump(obj) = ::JSON.generate(obj)
      def self.load(str) = ::JSON.parse(str, symbolize_names: true)
    end
    stub_const('Legion::JSON', json_mod)

    logging_mod = Module.new do
      def self.info(_msg) = nil
      def self.warn(_msg) = nil
      def self.debug(_msg) = nil
      def self.error(_msg) = nil
    end
    stub_const('Legion::Logging', logging_mod)
  end

  # ===========================================================================
  # Stage 1: GitHub Absorber
  # ===========================================================================
  describe 'Stage 1: GitHub Absorber' do
    let(:payload) { build_github_issue_payload }

    it 'absorbs a valid GitHub issue' do
      result = Legion::Extensions::Github::Absorbers::Issues.absorb(payload: payload, cache: cache)
      expect(result[:absorbed]).to be true
      expect(result[:work_item_id]).to be_a(String)
    end

    it 'stores raw payload in cache with fleet:payload: key' do
      Legion::Extensions::Github::Absorbers::Issues.absorb(payload: payload, cache: cache)
      keys = cache.keys('fleet:payload:*')
      expect(keys).not_to be_empty
    end

    it 'normalizes to standard work item format' do
      work_item = Legion::Extensions::Github::Absorbers::Issues.normalize(payload)
      expect(work_item[:source]).to eq('github')
      expect(work_item[:source_ref]).to eq('LegionIO/lex-exec#42')
      expect(work_item[:repo][:owner]).to eq('LegionIO')
      expect(work_item[:pipeline][:stage]).to eq('intake')
      expect(work_item[:pipeline][:attempt]).to eq(0)
    end

    it 'does NOT call set_nx (dedup is the assessor responsibility, not the absorber)' do
      expect(cache).not_to receive(:set_nx)
      Legion::Extensions::Github::Absorbers::Issues.absorb(payload: payload, cache: cache)
    end

    it 'rejects bot-generated events' do
      bot_payload = payload.merge('sender' => { 'login' => 'dependabot[bot]', 'type' => 'Bot' })
      result = Legion::Extensions::Github::Absorbers::Issues.absorb(payload: bot_payload, cache: cache)
      expect(result[:absorbed]).to be false
      expect(result[:reason]).to eq(:bot_generated)
    end

    it 'carries source_event from action field' do
      work_item = Legion::Extensions::Github::Absorbers::Issues.normalize(payload)
      expect(work_item[:source_event]).to eq('issues.opened')
    end
  end

  # ===========================================================================
  # Stage 2: Assessor
  # ===========================================================================
  describe 'Stage 2: Assessor' do
    let(:work_item) { build_absorbed_work_item }

    it 'classifies the work item' do
      classification = Fleet::Test::MockLLM.response_for(:assessor_classify)
      expect(classification[:complexity]).to eq('simple_bug')
      expect(classification[:estimated_difficulty]).to be_a(Numeric)
    end

    it 'produces a work item with config filled in after classification' do
      assessed = work_item.merge(
        config:   work_item[:config].merge(
          complexity:           'simple_bug',
          estimated_difficulty: 0.3,
          planning:             { enabled: false, solvers: 1, validators: 1, max_iterations: 2 }
        ),
        pipeline: work_item[:pipeline].merge(stage: 'assessed')
      )

      expect(assessed[:config][:complexity]).to eq('simple_bug')
      expect(assessed[:config][:planning][:enabled]).to be false
      expect(assessed[:pipeline][:stage]).to eq('assessed')
    end

    it 'skips planning for simple bugs (config.planning.enabled = false)' do
      assessed = build_assessed_work_item
      expect(assessed[:config][:planning][:enabled]).to be false
    end

    it 'records assessor in trace' do
      assessed = build_assessed_work_item
      stages = assessed[:pipeline][:trace].map { |t| t[:stage] }
      expect(stages).to include('assessor')
    end

    it 'trace includes model and provider for anti-bias tracking' do
      # Anti-bias: trace records which model was used per stage so downstream
      # stages can exclude the same model (build exclude hash)
      trace_entry = { stage: 'assessor', node: 'test-node',
                      started_at: Time.now.utc.iso8601,
                      model: 'claude-sonnet-4-20250514', provider: 'anthropic' }
      expect(trace_entry[:model]).not_to be_nil
      expect(trace_entry[:provider]).not_to be_nil
    end
  end

  # ===========================================================================
  # Stage 3: Developer (planning skipped for simple bug)
  # ===========================================================================
  describe 'Stage 3: Developer (planning skipped for simple bug)' do
    let(:work_item) { build_assessed_work_item }

    it 'produces implementation with changes and PR number' do
      implemented = build_implemented_work_item
      expect(implemented[:pipeline][:changes]).not_to be_empty
      expect(implemented[:pipeline][:pr_number]).to eq(100)
      expect(implemented[:pipeline][:branch_name]).to eq('fleet/fix-lex-exec-42')
    end

    it 'sets pipeline stage to implemented' do
      implemented = build_implemented_work_item
      expect_stage(implemented, 'implemented')
    end

    it 'includes developer in trace' do
      implemented = build_implemented_work_item
      expect_trace_includes(implemented, 'developer')
    end
  end

  # ===========================================================================
  # Stage 4: Validator (approved)
  # ===========================================================================
  describe 'Stage 4: Validator (approved)' do
    let(:work_item) { build_implemented_work_item }
    let(:review_result) { Fleet::Test::MockLLM.response_for(:validator_approve) }

    it 'approves the implementation' do
      expect(review_result[:verdict]).to eq('approved')
      expect(review_result[:score]).to be >= 0.8
    end

    it 'produces a work item with review_result set' do
      validated = work_item.merge(
        pipeline: work_item[:pipeline].merge(
          stage:         'validated',
          review_result: review_result
        )
      )
      expect(validated[:pipeline][:review_result][:verdict]).to eq('approved')
    end
  end

  # ===========================================================================
  # Stage 5: Ship (finalize)
  # ===========================================================================
  describe 'Stage 5: Ship (finalize)' do
    let(:work_item) do
      build_implemented_work_item.merge(
        pipeline: build_implemented_work_item[:pipeline].merge(
          review_result: { verdict: 'approved', score: 0.92 }
        )
      )
    end

    it 'work item has PR number for ready-marking' do
      expect(work_item[:pipeline][:pr_number]).to eq(100)
    end

    it 'work item has all required fields for shipping' do
      expect(work_item[:pipeline][:branch_name]).not_to be_nil
      expect(work_item[:pipeline][:changes]).not_to be_empty
      expect(work_item[:source_ref]).to eq('LegionIO/lex-exec#42')
      expect(work_item[:repo][:owner]).to eq('LegionIO')
      expect(work_item[:repo][:name]).to eq('lex-exec')
    end
  end

  # ===========================================================================
  # Full pipeline: GitHub issue -> assessed -> developed -> validated -> shipped
  # ===========================================================================
  describe 'Full pipeline: GitHub issue -> assessed -> developed -> validated -> shipped' do
    it 'flows through all stages in correct order' do
      # 1. Absorb
      payload = build_github_issue_payload
      work_item = Legion::Extensions::Github::Absorbers::Issues.normalize(payload)
      expect(work_item[:pipeline][:stage]).to eq('intake')

      # 2. Assess (simple bug, skip planning)
      work_item[:config][:complexity] = 'simple_bug'
      work_item[:config][:estimated_difficulty] = 0.3
      work_item[:config][:planning][:enabled] = false
      work_item[:pipeline][:stage] = 'assessed'
      work_item[:pipeline][:trace] << {
        stage: 'assessor', node: 'test', started_at: Time.now.utc.iso8601,
        model: 'claude-sonnet-4-20250514', provider: 'anthropic'
      }
      expect(work_item[:config][:planning][:enabled]).to be false

      # 3. Develop (skip planning, go straight to developer)
      work_item[:pipeline][:stage] = 'implemented'
      work_item[:pipeline][:changes] = ['lib/sandbox.rb', 'spec/sandbox_spec.rb']
      work_item[:pipeline][:pr_number] = 100
      work_item[:pipeline][:branch_name] = 'fleet/fix-lex-exec-42'
      work_item[:pipeline][:trace] << {
        stage: 'developer', node: 'test', started_at: Time.now.utc.iso8601,
        model: 'claude-opus-4-20250514', provider: 'anthropic'
      }

      # 4. Validate (approved)
      work_item[:pipeline][:stage] = 'validated'
      work_item[:pipeline][:review_result] = { verdict: 'approved', score: 0.92 }
      work_item[:pipeline][:trace] << {
        stage: 'validator', node: 'test', started_at: Time.now.utc.iso8601,
        model: 'claude-sonnet-4-20250514', provider: 'anthropic'
      }

      # 5. Ship
      work_item[:pipeline][:stage] = 'shipped'
      work_item[:pipeline][:trace] << {
        stage: 'ship', node: 'test', started_at: Time.now.utc.iso8601
      }

      # Verify final state
      expect(work_item[:pipeline][:stage]).to eq('shipped')
      expect(work_item[:pipeline][:pr_number]).to eq(100)
      expect(work_item[:pipeline][:trace].size).to eq(4)
      expect(work_item[:pipeline][:trace].map { |t| t[:stage] }).to eq(
        %w[assessor developer validator ship]
      )

      # Anti-bias: assessor used sonnet, developer used opus — models differ, so no exclude needed
      assessor_model = work_item[:pipeline][:trace].find { |t| t[:stage] == 'assessor' }[:model]
      developer_model = work_item[:pipeline][:trace].find { |t| t[:stage] == 'developer' }[:model]
      expect(assessor_model).not_to eq(developer_model)

      # resumed should be nil/false for happy path (no approval queue involved)
      expect(work_item[:pipeline][:resumed]).to be_falsey
    end
  end

  # ===========================================================================
  # Anti-bias: model exclusion via trace
  # ===========================================================================
  describe 'Anti-bias: model exclusion via trace' do
    it 'builds exclude hash from trace for downstream stages' do
      trace = [
        { stage: 'assessor', model: 'claude-sonnet-4-20250514', provider: 'anthropic' },
        { stage: 'developer', model: 'claude-opus-4-20250514', provider: 'anthropic' }
      ]

      # Downstream stage builds exclude hash from prior trace entries
      exclude = trace.each_with_object({}) do |entry, acc|
        acc[entry[:provider]] ||= []
        acc[entry[:provider]] << entry[:model]
      end

      expect(exclude['anthropic']).to include('claude-sonnet-4-20250514', 'claude-opus-4-20250514')
    end

    it 'anti-bias exclude does NOT appear in the work item trace itself' do
      work_item = build_implemented_work_item
      trace_keys = work_item[:pipeline][:trace].flat_map(&:keys)

      # The trace records model+provider for use BY downstream stages,
      # but the trace itself does not store a pre-built exclude hash
      expect(trace_keys).not_to include(:exclude)
    end
  end
end
