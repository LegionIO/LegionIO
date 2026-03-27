# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers'
require 'legion/extensions/actors/absorber_dispatch'

RSpec.describe Legion::Extensions::Actors::AbsorberDispatch do
  let(:test_absorber) do
    Class.new(Legion::Extensions::Absorbers::Base) do
      pattern :url, 'example.com/test/*'
      description 'Test absorber'
      def self.name = 'TestDispatchAbsorber'

      def handle(url: nil, **_opts)
        { success: true, url: url }
      end
    end
  end

  before do
    Legion::Extensions::Absorbers::PatternMatcher.reset!
    Legion::Extensions::Absorbers::PatternMatcher.register(test_absorber)
  end

  after { Legion::Extensions::Absorbers::PatternMatcher.reset! }

  describe '.dispatch' do
    it 'resolves input and calls the matching absorber' do
      result = described_class.dispatch(
        input:  'https://example.com/test/doc1',
        job_id: 'test-123'
      )
      expect(result[:success]).to be true
      expect(result[:absorber]).to include('TestDispatchAbsorber')
      expect(result[:job_id]).to eq('test-123')
    end

    it 'returns the absorber result' do
      result = described_class.dispatch(
        input:  'https://example.com/test/doc1',
        job_id: 'test-124'
      )
      expect(result[:result][:url]).to eq('https://example.com/test/doc1')
    end

    it 'generates a job_id when not provided' do
      result = described_class.dispatch(input: 'https://example.com/test/doc1')
      expect(result[:job_id]).not_to be_nil
      expect(result[:job_id].length).to eq(16)
    end

    it 'returns failure when no absorber matches' do
      result = described_class.dispatch(
        input:  'https://unknown.com/page',
        job_id: 'test-456'
      )
      expect(result[:success]).to be false
      expect(result[:error]).to include('no handler')
    end

    it 'returns failure when absorber raises' do
      error_absorber = Class.new(Legion::Extensions::Absorbers::Base) do
        pattern :url, 'error.com/*'
        def self.name = 'ErrorAbsorber'
        def handle(**) = raise('boom')
      end
      Legion::Extensions::Absorbers::PatternMatcher.register(error_absorber)

      result = described_class.dispatch(
        input:  'https://error.com/test',
        job_id: 'test-789'
      )
      expect(result[:success]).to be false
      expect(result[:error]).to include('boom')
    end

    it 'passes context content to the absorber' do
      content_absorber = Class.new(Legion::Extensions::Absorbers::Base) do
        pattern :url, 'content.com/*'
        def self.name = 'ContentAbsorber'

        def handle(content: nil, **_opts)
          { received_content: content }
        end
      end
      Legion::Extensions::Absorbers::PatternMatcher.register(content_absorber)

      result = described_class.dispatch(
        input:   'https://content.com/doc',
        job_id:  'test-content',
        context: { content: 'pre-fetched data' }
      )
      expect(result[:success]).to be true
      expect(result[:result][:received_content]).to eq('pre-fetched data')
    end
  end
end
