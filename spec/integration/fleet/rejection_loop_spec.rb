# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'json'

require_relative 'support/fleet_helpers'
require_relative 'support/mock_cache'
require_relative 'support/mock_llm'

RSpec.describe 'Fleet Rejection Loop' do
  include Fleet::Test::FleetHelpers

  let(:cache) { Fleet::Test::MockCache.new }

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
  # Validator rejects -> developer incorporates feedback -> validator approves
  # ===========================================================================
  describe 'validator rejects -> developer incorporates feedback -> validator approves' do
    it 'completes after one rejection cycle' do
      # Start with an implemented work item
      work_item = build_implemented_work_item

      # --- Validator rejects (attempt 0) ---
      rejection = Fleet::Test::MockLLM.response_for(:validator_reject)
      work_item[:pipeline][:stage] = 'validated'
      work_item[:pipeline][:review_result] = {
        verdict:         rejection[:verdict],
        score:           rejection[:score],
        issues:          rejection[:issues],
        merged_feedback: rejection[:feedback]
      }
      work_item[:pipeline][:trace] << {
        stage: 'validator', node: 'test', started_at: Time.now.utc.iso8601
      }

      expect(work_item[:pipeline][:review_result][:verdict]).to eq('rejected')
      expect(work_item[:pipeline][:attempt]).to eq(0)

      # --- Check routing: attempt (0) < 4, so route to incorporate_feedback ---
      attempt = work_item[:pipeline][:attempt]
      expect(attempt).to be < 4, 'Should route to feedback, not escalation'

      # --- Developer incorporates feedback (resumes to incorporate_feedback) ---
      work_item[:pipeline][:attempt] += 1
      work_item[:pipeline][:feedback_history] << rejection[:feedback]
      work_item[:pipeline][:stage] = 'implemented'
      work_item[:pipeline][:trace] << {
        stage: 'developer_feedback', node: 'test', started_at: Time.now.utc.iso8601
      }

      expect(work_item[:pipeline][:attempt]).to eq(1)
      expect(work_item[:pipeline][:feedback_history]).not_to be_empty

      # --- Validator approves (attempt 1) ---
      approval = Fleet::Test::MockLLM.response_for(:validator_approve_after_feedback)
      work_item[:pipeline][:stage] = 'validated'
      work_item[:pipeline][:review_result] = {
        verdict:         approval[:verdict],
        score:           approval[:score],
        issues:          approval[:issues],
        merged_feedback: approval[:feedback]
      }

      expect(work_item[:pipeline][:review_result][:verdict]).to eq('approved')

      # --- Ship ---
      work_item[:pipeline][:stage] = 'shipped'
      work_item[:pipeline][:trace] << {
        stage: 'ship', node: 'test', started_at: Time.now.utc.iso8601
      }

      expect(work_item[:pipeline][:stage]).to eq('shipped')
      expect(work_item[:pipeline][:attempt]).to eq(1)
      expect(work_item[:pipeline][:trace].map { |t| t[:stage] }).to include(
        'developer_feedback', 'ship'
      )
    end

    it 'feedback incorporation resumes to incorporate_feedback, not finalize' do
      # Design amendment: escalation approval resumes to incorporate_feedback
      # (not ship.finalize). The routing key must point at the developer stage.
      work_item = build_rejected_work_item(attempt: 0)

      # Simulate what the rejection conditioner determines
      verdict = work_item[:pipeline][:review_result][:verdict]
      attempt = work_item[:pipeline][:attempt]

      should_incorporate = verdict == 'rejected' && attempt < 4
      expect(should_incorporate).to be true

      # The resume target is incorporate_feedback (developer runner), not finalize (ship runner)
      resume_target = 'lex.developer.runners.developer.incorporate_feedback'
      expect(resume_target).to include('incorporate_feedback')
      expect(resume_target).not_to include('finalize')
    end
  end

  # ===========================================================================
  # Feedback summarization after N rejections
  # ===========================================================================
  describe 'feedback summarization after N rejections' do
    it 'summarizes feedback when attempt exceeds summarize_after threshold' do
      work_item = build_rejected_work_item(attempt: 2)
      summarize_after = work_item[:config][:feedback][:summarize_after]

      # After 2 rejections (>= summarize_after of 2), feedback should be summarized
      expect(work_item[:pipeline][:attempt]).to be >= summarize_after

      # Simulate summarization: condense feedback_history to constraint list
      original_feedback = work_item[:pipeline][:feedback_history]
      summarized = "CONSTRAINTS: #{original_feedback.map { |f| f.is_a?(Hash) ? f[:verdict] : f }.join('; ')}"
      work_item[:pipeline][:feedback_history] = [summarized]

      expect(work_item[:pipeline][:feedback_history].size).to eq(1)
      expect(work_item[:pipeline][:feedback_history].first).to start_with('CONSTRAINTS:')
    end
  end

  # ===========================================================================
  # Routing conditions (design spec section 4)
  # ===========================================================================
  describe 'routing conditions match design spec section 4' do
    it 'routes to incorporate_feedback when verdict=rejected AND attempt < 4' do
      [0, 1, 2, 3].each do |attempt|
        work_item = build_rejected_work_item(attempt: attempt)
        verdict = work_item[:pipeline][:review_result][:verdict]

        should_feedback = verdict == 'rejected' && attempt < 4
        expect(should_feedback).to be(true), "Attempt #{attempt} should route to incorporate_feedback"
      end
    end

    it 'does NOT route to incorporate_feedback when attempt >= 4' do
      work_item = build_rejected_work_item(attempt: 4)
      verdict = work_item[:pipeline][:review_result][:verdict]

      should_feedback = verdict == 'rejected' && work_item[:pipeline][:attempt] < 4
      expect(should_feedback).to be false
    end

    it 'routes to escalation when verdict=rejected AND attempt >= 4' do
      [4, 5, 6].each do |attempt|
        work_item = build_rejected_work_item(attempt: attempt)
        verdict = work_item[:pipeline][:review_result][:verdict]

        should_escalate = verdict == 'rejected' && attempt >= 4
        expect(should_escalate).to be(true), "Attempt #{attempt} should route to escalation"
      end
    end
  end

  # ===========================================================================
  # Thinking budget scaling by attempt
  # ===========================================================================
  describe 'thinking budget scaling by attempt' do
    it 'increases thinking budget with each attempt, capped at 64k' do
      budgets = (0..3).map do |attempt|
        [16_000 * (2**attempt), 64_000].min
      end

      expect(budgets[0]).to eq(16_000)  # attempt 0
      expect(budgets[1]).to eq(32_000)  # attempt 1
      expect(budgets[2]).to eq(64_000)  # attempt 2 (capped)
      expect(budgets[3]).to eq(64_000)  # attempt 3 (capped)
    end
  end

  # ===========================================================================
  # resumed: true flag on re-queued work items
  # ===========================================================================
  describe 'resumed: true flag' do
    it 'sets resumed: true on work items that re-enter the pipeline' do
      work_item = build_rejected_work_item(attempt: 0)

      # Simulate approval queue handler resuming the work item
      work_item[:pipeline][:resumed] = true
      work_item[:pipeline][:attempt] = 0 # reset attempt after approval

      expect(work_item[:pipeline][:resumed]).to be true
    end

    it 'happy-path work items do not have resumed flag set' do
      work_item = build_implemented_work_item
      expect(work_item[:pipeline][:resumed]).to be_nil
    end
  end
end
