# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/dispatch'
require 'legion/extensions/absorbers/transport'
require 'legion/extensions/absorbers/base'

RSpec.describe 'Absorber pipeline end-to-end', :integration do
  # Run without live AMQP/Redis (lite-mode semantics: transport_available? returns false)
  around do |example|
    orig = ENV.fetch('LEGION_MODE', nil)
    ENV['LEGION_MODE'] = 'lite'
    example.run
  ensure
    orig ? ENV['LEGION_MODE'] = orig : ENV.delete('LEGION_MODE')
  end

  after do
    Legion::Extensions::Absorbers::PatternMatcher.reset!
    Legion::Extensions::Absorbers::Dispatch.reset_dispatched!
  end

  # ---------------------------------------------------------------------------
  # Test absorber: matches example.com/absorb/* and calls absorb_raw
  # ---------------------------------------------------------------------------
  let(:absorber_name) { 'Legion::Extensions::Test::Absorbers::Content' }

  let(:test_absorber_class) do
    klass = Class.new(Legion::Extensions::Absorbers::Base) do
      pattern :url, 'example.com/absorb/*', priority: 10
      description 'Test absorber for pipeline integration spec'

      def absorb(url: nil, content: nil, metadata: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
        absorb_raw(content: "Absorbed: #{url}", tags: %w[test integration])
      end
    end
    klass.define_singleton_method(:name) { 'Legion::Extensions::Test::Absorbers::Content' }
    klass
  end

  before { Legion::Extensions::Absorbers::PatternMatcher.register(test_absorber_class) }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  def fake_apollo
    calls = []
    mod = Module.new
    mod.define_singleton_method(:ingest) do |content:, tags: [], **|
      calls << { content: content, tags: tags }
      { success: true }
    end
    mod.define_singleton_method(:started?) { true }
    [mod, calls]
  end

  # ===========================================================================
  # 1. PatternMatcher resolution
  # ===========================================================================
  describe 'step 1: PatternMatcher resolves URL to absorber class' do
    it 'returns the registered absorber for a matching URL' do
      resolved = Legion::Extensions::Absorbers::PatternMatcher.resolve('https://example.com/absorb/meeting-123')
      expect(resolved).to eq(test_absorber_class)
    end

    it 'returns nil for an unregistered URL' do
      resolved = Legion::Extensions::Absorbers::PatternMatcher.resolve('https://other.example.org/page')
      expect(resolved).to be_nil
    end
  end

  # ===========================================================================
  # 2. Dispatch routing
  # ===========================================================================
  describe 'step 2: Dispatch routes URL and records the request' do
    let(:test_url) { 'https://example.com/absorb/item-42' }

    it 'returns a dispatch record with required fields' do
      record = Legion::Extensions::Absorbers::Dispatch.dispatch(test_url)

      expect(record).not_to be_nil
      expect(record[:status]).to eq(:dispatched)
      expect(record[:absorb_id]).to match(/\Aabsorb:[0-9a-f-]+\z/)
      expect(record[:input]).to eq(test_url)
      expect(record[:absorber_class]).to eq(absorber_name)
    end

    it 'stores the record in the dispatched list' do
      Legion::Extensions::Absorbers::Dispatch.dispatch(test_url)

      dispatched = Legion::Extensions::Absorbers::Dispatch.dispatched
      expect(dispatched.size).to eq(1)
      expect(dispatched.first[:input]).to eq(test_url)
    end

    it 'carries context through to the dispatch record' do
      record = Legion::Extensions::Absorbers::Dispatch.dispatch(test_url,
                                                                context: { conversation_id: 'conv-test-1',
                                                                           requested_by:    'chat' })
      expect(record[:context][:conversation_id]).to eq('conv-test-1')
      expect(record[:context][:requested_by]).to eq('chat')
    end

    it 'does not call AMQP transport when not connected (lite mode)' do
      expect(Legion::Extensions::Absorbers::Transport).not_to receive(:publish_absorb_request)
      Legion::Extensions::Absorbers::Dispatch.dispatch(test_url)
    end

    it 'appends the absorb_id to the ancestor_chain in context' do
      record = Legion::Extensions::Absorbers::Dispatch.dispatch(test_url)
      chain  = record[:context][:ancestor_chain]
      expect(chain).to include(record[:absorb_id])
    end
  end

  # ===========================================================================
  # 3. Depth limiting and cycle detection
  # ===========================================================================
  describe 'step 2: dispatch safety guards' do
    it 'returns depth_exceeded when depth >= max_depth' do
      result = Legion::Extensions::Absorbers::Dispatch.dispatch(
        'https://example.com/absorb/deep',
        context: { depth: 5, max_depth: 5 }
      )
      expect(result[:status]).to eq(:depth_exceeded)
    end

    it 'returns cycle_detected when URL already in ancestor_chain' do
      result = Legion::Extensions::Absorbers::Dispatch.dispatch(
        'https://example.com/absorb/loop',
        context: { ancestor_chain: ['absorb:example.com/absorb/loop'] }
      )
      expect(result[:status]).to eq(:cycle_detected)
    end
  end

  # ===========================================================================
  # 4. Absorber execution → Apollo ingestion
  # ===========================================================================
  describe 'step 3: absorber calls absorb_raw → Apollo.ingest receives content' do
    let(:test_url) { 'https://example.com/absorb/transcript-99' }

    it 'absorber delivers content to Apollo when available' do
      apollo, calls = fake_apollo
      stub_const('Legion::Apollo', apollo)

      absorber = test_absorber_class.new
      absorber.absorb(url: test_url)

      expect(calls.size).to eq(1)
      expect(calls.first[:content]).to include(test_url)
      expect(calls.first[:tags]).to include('test', 'integration')
    end

    it 'absorber returns failure hash when Apollo is not available' do
      # Stub Apollo with a module that fails the apollo_available? check
      unavailable = Module.new
      unavailable.define_singleton_method(:ingest) { |**| raise 'should not be called' }
      # started? returns false → apollo_available? returns false
      unavailable.define_singleton_method(:started?) { false }
      stub_const('Legion::Apollo', unavailable)

      absorber = test_absorber_class.new
      result   = absorber.absorb(url: test_url)

      expect(result[:success]).to be false
      expect(result[:error]).to eq(:apollo_not_available)
    end
  end

  # ===========================================================================
  # 5. Full pipeline: drop URL → dispatch → absorb → Apollo
  # ===========================================================================
  describe 'full pipeline' do
    let(:test_url) { 'https://example.com/absorb/full-pipeline-test' }

    it 'URL dropped via Dispatch lands as a chunk in Apollo' do
      apollo, calls = fake_apollo
      stub_const('Legion::Apollo', apollo)

      record = Legion::Extensions::Absorbers::Dispatch.dispatch(test_url)
      expect(record[:status]).to eq(:dispatched)

      # Simulate what an actor does: instantiate the absorber and call absorb
      absorber = test_absorber_class.new
      result   = absorber.absorb(url: record[:input], context: record[:context])

      expect(result[:success]).to be true
      expect(calls).not_to be_empty
      expect(calls.first[:content]).to include('full-pipeline-test')
      expect(calls.first[:tags]).to include('integration')
    end
  end
end
