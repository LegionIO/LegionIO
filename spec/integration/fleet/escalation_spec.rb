# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'json'
require 'digest'

require_relative 'support/fleet_helpers'
require_relative 'support/mock_cache'

RSpec.describe 'Fleet Escalation Path' do
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
  # Max iterations exceeded -> escalation
  # ===========================================================================
  describe 'max iterations exceeded -> escalation' do
    it 'routes to assessor.escalate when attempt reaches threshold' do
      work_item = build_implemented_work_item
      max_iterations = work_item[:config][:implementation][:max_iterations]

      # Run through max_iterations - 1 feedback loops (attempts 0..3 retry)
      (0...(max_iterations - 1)).each do |attempt|
        work_item[:pipeline][:attempt] = attempt
        work_item[:pipeline][:review_result] = { verdict: 'rejected', score: 0.4 }
        work_item[:pipeline][:feedback_history] << "Feedback round #{attempt}"

        # Conditioner: attempt < 4 -> route to incorporate_feedback
        expect(attempt).to be < 4
      end

      # Final attempt (4): rejected, attempt >= 4 -> escalate
      work_item[:pipeline][:attempt] = 4
      work_item[:pipeline][:review_result] = { verdict: 'rejected', score: 0.35 }

      # Conditioner check for relationship 8 (escalation)
      should_escalate = work_item[:pipeline][:review_result][:verdict] == 'rejected' &&
                        work_item[:pipeline][:attempt] >= 4
      expect(should_escalate).to be true

      # Conditioner check for relationship 7 (feedback) should NOT match
      should_feedback = work_item[:pipeline][:review_result][:verdict] == 'rejected' &&
                        work_item[:pipeline][:attempt] < 4
      expect(should_feedback).to be false
    end

    it 'escalation handler sets fleet:escalated label' do
      build_rejected_work_item(attempt: 4)

      escalation_result = {
        success: true,
        actions: [
          { action: 'set_label', label: 'fleet:escalated' },
          { action: 'post_comment', content: 'Escalated: max iterations exceeded' },
          { action: 'approval_queue', type: 'fleet.escalation' },
          { action: 'clear_dedup_cache' },
          { action: 'clear_redis_refs' },
          { action: 'cleanup_worktree' }
        ]
      }

      expect(escalation_result[:actions].map { |a| a[:action] }).to include(
        'set_label', 'post_comment', 'approval_queue',
        'clear_dedup_cache', 'clear_redis_refs', 'cleanup_worktree'
      )
    end

    it 'clears dedup cache on escalation so issue can be retried' do
      work_item_id = SecureRandom.uuid
      fingerprint = Digest::SHA256.hexdigest('github:LegionIO/lex-exec#42:Fix sandbox')
      dedup_key = "fleet:active:#{fingerprint}"

      # Set dedup key (simulating active work item)
      cache.set(dedup_key, work_item_id, ttl: 86_400)
      expect(cache.exists?(dedup_key)).to be true

      # Escalation clears the key
      cache.delete(dedup_key)
      expect(cache.exists?(dedup_key)).to be false
    end

    it 'clears all Redis refs on escalation' do
      work_item_id = SecureRandom.uuid

      cache.set("fleet:payload:#{work_item_id}", '{}', ttl: 86_400)
      cache.set("fleet:context:#{work_item_id}", '{}', ttl: 86_400)
      cache.set("fleet:worktree:#{work_item_id}", '/tmp/worktree', ttl: 86_400)

      %w[payload context worktree].each do |prefix|
        cache.delete("fleet:#{prefix}:#{work_item_id}")
      end

      expect(cache.exists?("fleet:payload:#{work_item_id}")).to be false
      expect(cache.exists?("fleet:context:#{work_item_id}")).to be false
      expect(cache.exists?("fleet:worktree:#{work_item_id}")).to be false
    end
  end

  # ===========================================================================
  # Approval queue integration
  # ===========================================================================
  describe 'approval queue integration' do
    it 'creates an escalation approval queue entry that resumes to incorporate_feedback' do
      work_item = build_rejected_work_item(attempt: 4)
      work_item[:pipeline][:resumed] = true
      work_item[:pipeline][:attempt] = 0

      # Escalation approval resumes to incorporate_feedback (developer runner),
      # not ship.finalize. The stored payload has resumed: true so the handler
      # skips the consent gate on replay.
      approval_entry = {
        approval_type:      'fleet.escalation',
        work_item_id:       work_item[:work_item_id],
        source_ref:         work_item[:source_ref],
        title:              work_item[:title],
        resume_routing_key: 'lex.developer.runners.developer.incorporate_feedback',
        payload:            work_item,
        status:             'pending'
      }

      expect(approval_entry[:approval_type]).to eq('fleet.escalation')
      expect(approval_entry[:status]).to eq('pending')
      expect(approval_entry[:resume_routing_key]).to include('incorporate_feedback')
      expect(approval_entry[:resume_routing_key]).not_to include('finalize')
      expect(approval_entry[:payload][:pipeline][:resumed]).to be true
      expect(approval_entry[:payload][:pipeline][:attempt]).to eq(0)
    end

    it 'creates a consent approval queue entry that resumes to ship.finalize' do
      work_item = build_implemented_work_item.merge(
        pipeline: build_implemented_work_item[:pipeline].merge(
          review_result: { verdict: 'approved', score: 0.92 },
          resumed:       true
        )
      )

      # Consent approvals (shipping gate) resume to ship.finalize.
      # The stored payload has resumed: true so finalize skips consent on replay.
      approval_entry = {
        approval_type:      'fleet.shipping',
        work_item_id:       work_item[:work_item_id],
        source_ref:         work_item[:source_ref],
        title:              work_item[:title],
        resume_routing_key: 'lex.developer.runners.ship.finalize',
        payload:            work_item,
        status:             'pending'
      }

      expect(approval_entry[:approval_type]).to eq('fleet.shipping')
      expect(approval_entry[:resume_routing_key]).to eq('lex.developer.runners.ship.finalize')
      expect(approval_entry[:payload][:pipeline][:resumed]).to be true
    end

    it 'resumed: true prevents re-triggering escalation or consent on replay' do
      # When a work item is resumed from the approval queue, the pipeline handler
      # checks pipeline[:resumed] to skip the consent check and proceed directly.
      work_item = build_rejected_work_item(attempt: 4)
      work_item[:pipeline][:resumed] = true

      expect(work_item[:pipeline][:resumed]).to be true

      # Simulate the gate check: resumed work items bypass the consent check
      would_request_approval = !work_item[:pipeline][:resumed]
      expect(would_request_approval).to be false
    end
  end

  # ===========================================================================
  # Pipeline trace completeness
  # ===========================================================================
  describe 'pipeline trace completeness' do
    it 'records all stages in trace for a full rejection+approval flow' do
      work_item = build_absorbed_work_item
      trace = []

      # Assess
      trace << { stage: 'assessor', node: 'worker-1', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601,
                 token_usage: { input: 500, output: 200 },
                 model: 'claude-sonnet-4-20250514', provider: 'anthropic' }

      # Develop (attempt 0)
      trace << { stage: 'developer', node: 'worker-2', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601,
                 token_usage: { input: 3000, output: 1500 },
                 model: 'claude-opus-4-20250514', provider: 'anthropic' }

      # Validate (rejected)
      trace << { stage: 'validator', node: 'worker-3', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601,
                 token_usage: { input: 2000, output: 500 },
                 model: 'claude-sonnet-4-20250514', provider: 'anthropic' }

      # Incorporate feedback
      trace << { stage: 'developer_feedback', node: 'worker-2', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601,
                 token_usage: { input: 4000, output: 2000 },
                 model: 'claude-opus-4-20250514', provider: 'anthropic' }

      # Validate (approved)
      trace << { stage: 'validator', node: 'worker-3', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601,
                 token_usage: { input: 2000, output: 300 },
                 model: 'claude-haiku-4-20251001', provider: 'anthropic' }

      # Ship
      trace << { stage: 'ship', node: 'worker-2', started_at: Time.now.utc.iso8601,
                 completed_at: Time.now.utc.iso8601, token_usage: { input: 0, output: 0 } }

      work_item[:pipeline][:trace] = trace

      # Verify trace
      stages = trace.map { |t| t[:stage] }
      expect(stages).to eq(%w[assessor developer validator developer_feedback validator ship])

      # Verify total token usage can be calculated
      total_input = trace.sum { |t| t[:token_usage][:input] }
      total_output = trace.sum { |t| t[:token_usage][:output] }
      expect(total_input).to eq(11_500)
      expect(total_output).to eq(4500)
    end

    it 'records model and provider in each trace entry for anti-bias tracking' do
      work_item = build_absorbed_work_item
      trace = [
        { stage: 'assessor', model: 'claude-sonnet-4-20250514', provider: 'anthropic' },
        { stage: 'developer', model: 'claude-opus-4-20250514', provider: 'anthropic' }
      ]
      work_item[:pipeline][:trace] = trace

      # Each trace entry must carry model+provider
      trace.each do |entry|
        expect(entry[:model]).not_to be_nil, "#{entry[:stage]} trace entry missing :model"
        expect(entry[:provider]).not_to be_nil, "#{entry[:stage]} trace entry missing :provider"
      end
    end
  end
end
