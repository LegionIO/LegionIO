# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/matchers/base'
require 'legion/extensions/absorbers/matchers/url'
require 'legion/extensions/absorbers/base'

RSpec.describe Legion::Extensions::Absorbers::Base do
  let(:test_absorber) do
    Class.new(described_class) do
      pattern :url, 'example.com/docs/*'
      pattern :url, 'example.com/files/*', priority: 50
      description 'Test absorber for specs'

      def handle(url: nil, content: nil, _metadata: {}, _context: {})
        { absorbed: true, url: url, content: content }
      end
    end
  end

  describe '.pattern' do
    it 'registers patterns on the class' do
      expect(test_absorber.patterns.length).to eq(2)
    end

    it 'stores type, value, and priority' do
      pat = test_absorber.patterns.first
      expect(pat[:type]).to eq(:url)
      expect(pat[:value]).to eq('example.com/docs/*')
      expect(pat[:priority]).to eq(100)
    end

    it 'allows custom priority' do
      pat = test_absorber.patterns.last
      expect(pat[:priority]).to eq(50)
    end
  end

  describe '.description' do
    it 'stores description text' do
      expect(test_absorber.description).to eq('Test absorber for specs')
    end
  end

  describe '.patterns' do
    it 'returns empty array when no patterns defined' do
      bare = Class.new(described_class)
      expect(bare.patterns).to eq([])
    end
  end

  describe '#handle' do
    it 'raises NotImplementedError on base class' do
      expect { described_class.new.handle }.to raise_error(NotImplementedError)
    end

    it 'accepts url keyword' do
      result = test_absorber.new.handle(url: 'https://example.com/docs/a')
      expect(result[:url]).to eq('https://example.com/docs/a')
    end

    it 'accepts content keyword' do
      result = test_absorber.new.handle(content: 'raw text')
      expect(result[:content]).to eq('raw text')
    end
  end

  describe '#absorb_to_knowledge' do
    it 'responds to absorb_to_knowledge' do
      expect(test_absorber.new).to respond_to(:absorb_to_knowledge)
    end
  end

  describe '#absorb_raw' do
    it 'responds to absorb_raw' do
      expect(test_absorber.new).to respond_to(:absorb_raw)
    end
  end

  describe '#translate' do
    it 'raises when legion-data not available' do
      absorber = test_absorber.new
      expect { absorber.translate('file.pdf') }.to raise_error(RuntimeError, /legion-data/) unless defined?(Legion::Data::Extract)
    end
  end

  describe '#report_progress' do
    it 'responds to report_progress' do
      expect(test_absorber.new).to respond_to(:report_progress)
    end

    it 'does not error without job_id' do
      expect { test_absorber.new.report_progress(message: 'test') }.not_to raise_error
    end
  end

  describe 'attr_accessors' do
    it 'has job_id accessor' do
      absorber = test_absorber.new
      absorber.job_id = 'abc123'
      expect(absorber.job_id).to eq('abc123')
    end

    it 'has runners accessor' do
      absorber = test_absorber.new
      absorber.runners = double('runners')
      expect(absorber.runners).not_to be_nil
    end
  end
end
