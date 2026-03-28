# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/dispatch'

RSpec.describe Legion::Extensions::Absorbers::Dispatch do
  before { described_class.reset_dispatched! if described_class.respond_to?(:reset_dispatched!) }

  describe '.dispatch' do
    let(:absorber_class) do
      Class.new(Legion::Extensions::Absorbers::Base) do
        pattern :url, 'example.com/*'
        def self.name = 'TestAbsorber'
      end
    end

    before do
      allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:resolve).and_return(absorber_class)
    end

    it 'resolves input to an absorber and returns dispatch metadata' do
      result = described_class.dispatch('https://example.com/item/123', context: { conversation_id: 'conv-1' })
      expect(result[:absorb_id]).to be_a(String)
      expect(result[:absorber_class]).to eq('TestAbsorber')
      expect(result[:status]).to eq(:dispatched)
    end

    it 'returns nil when no absorber matches' do
      allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:resolve).and_return(nil)
      result = described_class.dispatch('https://unknown.com/foo')
      expect(result).to be_nil
    end

    it 'respects max_depth and rejects over-depth requests' do
      result = described_class.dispatch('https://example.com/item/123',
                                        context: { depth: 5, max_depth: 5 })
      expect(result[:status]).to eq(:depth_exceeded)
    end

    it 'detects cycles via ancestor_chain' do
      result = described_class.dispatch('https://example.com/item/123',
                                        context: { ancestor_chain: ['absorb:example.com/item/123'] })
      expect(result[:status]).to eq(:cycle_detected)
    end
  end

  describe '.dispatch_children' do
    it 'dispatches each child with incremented depth' do
      children = [{ url: 'https://example.com/a' }, { url: 'https://example.com/b' }]
      allow(described_class).to receive(:dispatch).and_call_original
      allow(Legion::Extensions::Absorbers::PatternMatcher).to receive(:resolve).and_return(nil)

      results = described_class.dispatch_children(children,
                                                  parent_context: { depth: 0, max_depth: 5, ancestor_chain: [] })
      expect(results.size).to eq(2)
    end
  end
end
