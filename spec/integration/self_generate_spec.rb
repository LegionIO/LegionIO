# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Self-generating functions integration', :integration do
  # Test the full loop without real AMQP or LLM

  before do
    Legion::MCP::Observer.reset! if defined?(Legion::MCP::Observer)
    Legion::MCP::PatternStore.reset! if defined?(Legion::MCP::PatternStore)
    Legion::MCP::SelfGenerate.reset! if defined?(Legion::MCP::SelfGenerate)
    Legion::Extensions::Codegen::Helpers::GeneratedRegistry.reset! if defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry)
  end

  describe 'gap detection to generation' do
    it 'detects gaps from observer patterns' do
      next unless defined?(Legion::MCP::Observer) && defined?(Legion::MCP::GapDetector)

      # Seed unmatched intents — needs >= GAP_INTENT_THRESHOLD (5) with same normalized text
      6.times { Legion::MCP::Observer.record_intent('deploy application to production', nil) }

      gaps = Legion::MCP::GapDetector.detect_gaps
      expect(gaps).not_to be_empty
      expect(gaps.first).to have_key(:type)
      expect(gaps.first).to have_key(:priority)
    end
  end

  describe 'SelfGenerate cycle' do
    it 'publishes gaps when enabled' do
      next unless defined?(Legion::MCP::SelfGenerate) && defined?(Legion::MCP::Observer)

      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :enabled).and_return(true)
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :cooldown_seconds).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :max_gaps_per_cycle).and_return(nil)

      # Seed enough unmatched intents to cross the detection threshold
      6.times { Legion::MCP::Observer.record_intent('novel capability request', nil) }

      expect(Legion::MCP::SelfGenerate).to receive(:publish_gap).at_least(:once)
      result = Legion::MCP::SelfGenerate.run_cycle
      expect(result[:success]).to be true
      expect(result[:published]).to be >= 1
    end
  end

  describe 'tier classification' do
    it 'classifies simple gaps correctly' do
      next unless defined?(Legion::Extensions::Codegen::Helpers::TierClassifier)

      gap = { occurrence_count: 3 }
      expect(Legion::Extensions::Codegen::Helpers::TierClassifier.classify(gap: gap)).to eq(:simple)
    end

    it 'classifies complex gaps correctly' do
      next unless defined?(Legion::Extensions::Codegen::Helpers::TierClassifier)

      gap = { occurrence_count: 15 }
      expect(Legion::Extensions::Codegen::Helpers::TierClassifier.classify(gap: gap)).to eq(:complex)
    end
  end

  describe 'code review pipeline' do
    it 'validates clean code through syntax and security' do
      next unless defined?(Legion::Extensions::Eval::Runners::CodeReview)

      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :validation).and_return(
        { syntax_check: true, run_specs: false, llm_review: false, quality_gate: { enabled: false } }
      )

      code = <<~RUBY
        # frozen_string_literal: true

        module Legion
          module Generated
            module TestFunc
              extend self

              def handle(payload:)
                { success: true, processed: payload }
              end
            end
          end
        end
      RUBY

      result = Legion::Extensions::Eval::Runners::CodeReview.review_generated(
        code: code, spec_code: '', context: {}
      )
      expect(result[:passed]).to be true
      expect(result[:verdict]).to eq(:approve)
    end

    it 'rejects code with security violations' do
      next unless defined?(Legion::Extensions::Eval::Runners::CodeReview)

      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :validation).and_return(
        { syntax_check: true, run_specs: false, llm_review: false, quality_gate: { enabled: false } }
      )

      dangerous_code = "system('rm -rf /')"
      result = Legion::Extensions::Eval::Runners::CodeReview.review_generated(
        code: dangerous_code, spec_code: '', context: {}
      )
      expect(result[:passed]).to be false
    end
  end

  describe 'review handler verdict routing' do
    it 'approves and registers a generation' do
      next unless defined?(Legion::Extensions::Codegen::Helpers::GeneratedRegistry) &&
                  defined?(Legion::Extensions::Codegen::Runners::ReviewHandler)

      generation = {
        id: 'int_gen_001', gap_id: 'gap_int', gap_type: 'unmatched_intent',
        tier: 'simple', name: 'TestFunc', file_path: '/tmp/nonexistent.rb',
        spec_path: '/tmp/nonexistent_spec.rb', confidence: 0.95
      }

      Legion::Extensions::Codegen::Helpers::GeneratedRegistry.persist(generation: generation)

      result = Legion::Extensions::Codegen::Runners::ReviewHandler.handle_verdict(
        review: { generation_id: 'int_gen_001', verdict: :approve, confidence: 0.95 }
      )

      expect(result[:success]).to be true
      expect(result[:action]).to eq(:approved)

      record = Legion::Extensions::Codegen::Helpers::GeneratedRegistry.get(id: 'int_gen_001')
      expect(record[:status]).to eq('approved')
    end
  end

  describe 'MCP tool registry' do
    it 'supports dynamic tool registration' do
      next unless defined?(Legion::MCP::Server)

      tool_class = Class.new(::MCP::Tool) do
        tool_name 'test.integration_tool'
        description 'Integration test tool'
        input_schema(properties: {})
        def self.call(**) = ::MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end

      Legion::MCP::Server.register_tool(tool_class)
      expect(Legion::MCP::Server.tool_registry.map(&:tool_name)).to include('test.integration_tool')

      Legion::MCP::Server.unregister_tool('test.integration_tool')
      expect(Legion::MCP::Server.tool_registry.map(&:tool_name)).not_to include('test.integration_tool')
    end
  end

  describe 'function metadata DSL' do
    it 'stores and reads function metadata' do
      next unless defined?(Legion::Extensions::Helpers::Lex)

      # Use a real module under Legion::Extensions namespace so that Lex helpers resolve
      # segments/log/settings correctly via the Base mixin.
      mod = Module.new do
        extend self

        def settings
          @settings ||= { functions: {} }
        end

        def log
          @log ||= ::Logger.new(::File::NULL)
        end

        def respond_to?(name, include_private = false)
          return true if name == :my_func

          super
        end

        def my_func; end

        include Legion::Extensions::Helpers::Lex
      end

      mod.function_desc(:my_func, 'Test function')
      mod.function_expose(:my_func, true)
      mod.function_category(:my_func, :codegen)
      mod.function_tags(:my_func, %i[test integration])

      func = mod.settings[:functions][:my_func]
      expect(func[:desc]).to eq('Test function')
      expect(func[:expose]).to be true
      expect(func[:category]).to eq(:codegen)
      expect(func[:tags]).to eq(%i[test integration])
    end
  end
end
