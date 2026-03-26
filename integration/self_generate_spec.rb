# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require 'fileutils'

# Load core gems
require 'legion/json'
require 'legion/logging'
require 'legion/settings'

# Stub modules that may not be available in isolation
unless defined?(Legion::Transport::Messages::Dynamic)
  module Legion
    module Transport
      module Messages
        class Dynamic
          attr_reader :function, :data

          def initialize(function:, data:, **)
            @function = function
            @data = data
          end

          def publish
            Legion::Transport::Local.publish('codegen', @function, Legion::JSON.dump(@data))
          end
        end
      end
    end
  end
end

unless defined?(Legion::LLM)
  module Legion
    module LLM
      def self.chat(messages:, _caller: nil, **)
        messages.last[:content]
        code = <<~RUBY
          # frozen_string_literal: true

          module Legion
            module Generated
              module GreetUser
                extend self

                def greet(name:)
                  { success: true, greeting: "Hello, \#{name}!" }
                end
              end
            end
          end
        RUBY
        Struct.new(:content).new(code)
      end

      def self.respond_to_missing?(name, *)
        name == :chat || super
      end
    end
  end
end

# Load transport Local for InProcess mode
require 'legion/transport/local'

# Load codegen extension
begin
  require 'legion/extensions/codegen'
  LEGION_CODEGEN_EXTENSION_AVAILABLE = true
rescue LoadError => e
  LEGION_CODEGEN_EXTENSION_AVAILABLE = false
  warn "lex-codegen / legion codegen extension not available; skipping dependent behavior: #{e.message}"
end

# Load eval extension (only code_review runner + security evaluator)
begin
  require 'legion/extensions/eval'
  LEGION_EVAL_EXTENSION_AVAILABLE = true
rescue LoadError => e
  LEGION_EVAL_EXTENSION_AVAILABLE = false
  warn "lex-eval / legion eval extension not available; skipping dependent behavior: #{e.message}"
end

# Stub MCP Server if not available
unless defined?(Legion::MCP::Server)
  module Legion
    module MCP
      module Server
        @tool_registry = []
        @tool_registry_lock = Mutex.new

        class << self
          attr_reader :tool_registry

          def register_tool(tool_class)
            @tool_registry_lock.synchronize do
              return if tool_registry.any? { |tc| tc.respond_to?(:tool_name) && tc.tool_name == tool_class.tool_name }

              tool_registry << tool_class
            end
          end

          def unregister_tool(tool_name)
            @tool_registry_lock.synchronize do
              tool_registry.reject! { |tc| tc.respond_to?(:tool_name) && tc.tool_name == tool_name }
            end
          end

          def reset_caches!; end
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

RSpec.describe 'Self-Generating Functions End-to-End' do
  let(:output_dir) { Dir.mktmpdir('legion_e2e_codegen') }

  before do
    # Reset Local transport
    Legion::Transport::Local.reset! if Legion::Transport::Local.respond_to?(:reset!)

    # Reset GeneratedRegistry
    Legion::Extensions::Codegen::Helpers::GeneratedRegistry.reset!

    # Configure settings for test
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :enabled).and_return(true)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :cooldown_seconds).and_return(0)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :max_gaps_per_cycle).and_return(5)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :runner_method, :output_dir).and_return(output_dir)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :validation).and_return(
      { syntax_check: true, run_specs: false, llm_review: false, max_retries: 2 }
    )
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :corroboration, :enabled).and_return(false)
    allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :corroboration, :min_agents).and_return(2)
    allow(Legion::Settings).to receive(:dig).with(:node, :name).and_return('test-node')
    allow(Legion::Settings).to receive(:[]).and_return(nil)
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe 'gap detection -> generation -> validation -> registration' do
    let(:synthetic_gap) do
      {
        gap_id:           'gap_e2e_001',
        gap_type:         'unmatched_intent',
        intent:           'greet user',
        occurrence_count: 3,
        priority:         0.7,
        metadata:         {}
      }
    end

    it 'generates code from a gap and passes validation' do
      # Phase 1: GapSubscriber receives a gap and generates code
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)

      generation = subscriber.action(synthetic_gap)

      expect(generation[:success]).to be true
      expect(generation[:generation_id]).to start_with('gen_')
      expect(generation[:tier]).to eq(:simple)
      expect(generation[:code]).to include('module Legion')
      expect(generation[:file_path]).to start_with(output_dir)
      expect(File.exist?(generation[:file_path])).to be true
    end

    it 'validates generated code through the review pipeline' do
      # Phase 1: Generate
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(synthetic_gap)
      expect(generation[:success]).to be true

      # Phase 2: Review (simulating what CodeReviewSubscriber does)
      review = Legion::Extensions::Eval::Runners::CodeReview.review_generated(
        code:      generation[:code],
        spec_code: generation[:spec_code],
        context:   { gap_type: 'unmatched_intent', intent: 'greet user' }
      )

      expect(review[:passed]).to be true
      expect(review[:verdict]).to eq(:approve)
      expect(review[:confidence]).to be > 0.0
      expect(review[:stages][:syntax][:passed]).to be true
      expect(review[:stages][:security][:passed]).to be true
    end

    it 'registers approved code via ReviewHandler' do
      # Phase 1: Generate
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(synthetic_gap)
      expect(generation[:success]).to be true

      # Phase 2: Persist to registry
      registry_record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(
        generation: {
          id:        generation[:generation_id],
          gap_id:    generation[:gap_id],
          gap_type:  generation[:gap_type],
          tier:      generation[:tier],
          name:      'greet_user',
          file_path: generation[:file_path],
          spec_path: generation[:spec_path]
        }
      )
      expect(registry_record[:status]).to eq('pending')

      # Phase 3: Review
      review_result = {
        generation_id: generation[:generation_id],
        verdict:       :approve,
        confidence:    0.95,
        issues:        [],
        scores:        {}
      }

      # Phase 4: ReviewHandler processes the verdict
      result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(review: review_result)

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:approved)

      # Verify registry updated
      record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.get(id: generation[:generation_id])
      expect(record[:status]).to eq('approved')
    end

    it 'parks rejected code' do
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(synthetic_gap)
      expect(generation[:success]).to be true

      Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(
        generation: {
          id:        generation[:generation_id],
          gap_id:    generation[:gap_id],
          gap_type:  generation[:gap_type],
          tier:      generation[:tier],
          name:      'greet_user',
          file_path: generation[:file_path],
          spec_path: generation[:spec_path]
        }
      )

      result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
        review: { generation_id: generation[:generation_id], verdict: :reject, confidence: 0.1, issues: ['unsafe code'] }
      )

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:parked)

      record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.get(id: generation[:generation_id])
      expect(record[:status]).to eq('parked')
    end

    it 'retries on revise verdict up to max_retries then parks' do
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(synthetic_gap)
      expect(generation[:success]).to be true

      Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(
        generation: {
          id:            generation[:generation_id],
          gap_id:        generation[:gap_id],
          gap_type:      generation[:gap_type],
          tier:          generation[:tier],
          name:          'greet_user',
          file_path:     generation[:file_path],
          spec_path:     generation[:spec_path],
          attempt_count: 2
        }
      )

      result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
        review: { generation_id: generation[:generation_id], verdict: :revise, confidence: 0.4, issues: ['needs improvement'] }
      )

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:parked)
    end

    it 'exercises the full loop: generate -> validate -> register -> boot load' do
      # Step 1: Generate
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(synthetic_gap)
      expect(generation[:success]).to be true

      # Step 2: Validate
      review = Legion::Extensions::Eval::Runners::CodeReview.review_generated(
        code: generation[:code], spec_code: generation[:spec_code], context: {}
      )
      expect(review[:verdict]).to eq(:approve)

      # Step 3: Persist + Approve
      Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(
        generation: {
          id:        generation[:generation_id],
          gap_id:    generation[:gap_id],
          gap_type:  generation[:gap_type],
          tier:      generation[:tier],
          name:      'greet_user',
          file_path: generation[:file_path],
          spec_path: generation[:spec_path]
        }
      )

      Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
        review: { generation_id: generation[:generation_id], verdict: :approve, confidence: 0.95, issues: [] }
      )

      # Step 4: Boot load (simulates service restart)
      loaded = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.load_on_boot
      expect(loaded).to eq(1)

      # Step 5: Verify the generated module is actually loaded
      expect(defined?(Legion::Generated::GreetUser)).to be_truthy
      result = Legion::Generated::GreetUser.greet(name: 'World')
      expect(result[:success]).to be true
      expect(result[:greeting]).to eq('Hello, World!')
    end
  end

  describe 'tier classification' do
    it 'classifies low occurrence gaps as simple' do
      tier = Legion::Extensions::Codegen::Helpers::TierClassifier.classify(gap: { occurrence_count: 5 })
      expect(tier).to eq(:simple)
    end

    it 'classifies high occurrence gaps as complex' do
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :tier, :simple_max_occurrences).and_return(10)
      tier = Legion::Extensions::Codegen::Helpers::TierClassifier.classify(gap: { occurrence_count: 15 })
      expect(tier).to eq(:complex)
    end
  end

  describe 'ReviewSubscriber actor' do
    it 'routes verdict through ReviewHandler' do
      subscriber = Object.new
      subscriber.extend(Legion::Extensions::Codegen::Actor::GapSubscriber)
      generation = subscriber.action(
        gap_id: 'gap_rs_001', gap_type: 'unmatched_intent', intent: 'greet user',
        occurrence_count: 3, priority: 0.7
      )
      expect(generation[:success]).to be true

      Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(
        generation: {
          id:        generation[:generation_id],
          gap_id:    generation[:gap_id],
          gap_type:  generation[:gap_type],
          tier:      generation[:tier],
          name:      'greet_user',
          file_path: generation[:file_path],
          spec_path: generation[:spec_path]
        }
      )

      review_sub = Object.new
      review_sub.extend(Legion::Extensions::Codegen::Actor::ReviewSubscriber)

      result = review_sub.action(
        generation_id: generation[:generation_id],
        verdict:       'approve',
        confidence:    0.9,
        issues:        [],
        scores:        {}
      )

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:approved)
    end
  end
end
