# frozen_string_literal: true

require 'spec_helper'
require 'legion/auth/token_manager'
require 'legion/extensions/absorbers/matchers/base'
require 'legion/extensions/absorbers/matchers/url'
require 'legion/extensions/absorbers/base'

RSpec.describe Legion::Extensions::Absorbers::Base do
  let(:test_absorber) do
    Class.new(described_class) do
      pattern :url, 'example.com/docs/*'
      pattern :url, 'example.com/files/*', priority: 50
      description 'Test absorber for specs'

      def absorb(url: nil, content: nil, metadata: {}, context: {})
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

  describe '#absorb' do
    it 'raises NotImplementedError on base class' do
      expect { described_class.new.absorb }.to raise_error(NotImplementedError)
    end

    it 'accepts url keyword' do
      result = test_absorber.new.absorb(url: 'https://example.com/docs/a')
      expect(result[:url]).to eq('https://example.com/docs/a')
    end

    it 'accepts content keyword' do
      result = test_absorber.new.absorb(content: 'raw text')
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

  describe 'error constants' do
    it 'defines TokenRevocationError' do
      expect(described_class::TokenRevocationError.ancestors).to include(StandardError)
    end

    it 'defines TokenUnavailableError' do
      expect(described_class::TokenUnavailableError.ancestors).to include(StandardError)
    end
  end

  describe '#with_token' do
    let(:absorber) { test_absorber.new }
    let(:mock_manager) { instance_double(Legion::Auth::TokenManager) }

    before do
      allow(absorber).to receive(:token_manager_for).and_return(mock_manager)
    end

    it 'yields the token when valid' do
      allow(mock_manager).to receive(:token_valid?).and_return(true)
      allow(mock_manager).to receive(:revoked?).and_return(false)
      allow(mock_manager).to receive(:ensure_valid_token).and_return('valid-token')

      result = nil
      absorber.with_token(provider: :microsoft) { |t| result = t }
      expect(result).to eq('valid-token')
    end

    it 'raises TokenUnavailableError when no valid token' do
      allow(mock_manager).to receive(:token_valid?).and_return(false)
      expect { absorber.with_token(provider: :microsoft) { nil } }.to raise_error(described_class::TokenUnavailableError)
    end

    it 'raises TokenRevocationError when token is revoked' do
      allow(mock_manager).to receive(:token_valid?).and_return(true)
      allow(mock_manager).to receive(:revoked?).and_return(true)
      expect { absorber.with_token(provider: :microsoft) { nil } }.to raise_error(described_class::TokenRevocationError)
    end

    it 'raises TokenUnavailableError when refresh returns nil' do
      allow(mock_manager).to receive(:token_valid?).and_return(true)
      allow(mock_manager).to receive(:revoked?).and_return(false)
      allow(mock_manager).to receive(:ensure_valid_token).and_return(nil)
      expect { absorber.with_token(provider: :microsoft) { nil } }.to raise_error(described_class::TokenUnavailableError)
    end

    it 'wraps TokenExpiredError as TokenUnavailableError' do
      allow(mock_manager).to receive(:token_valid?).and_return(true)
      allow(mock_manager).to receive(:revoked?).and_return(false)
      allow(mock_manager).to receive(:ensure_valid_token).and_raise(Legion::Auth::TokenManager::TokenExpiredError, 'expired')
      expect { absorber.with_token(provider: :microsoft) { nil } }.to raise_error(described_class::TokenUnavailableError, 'expired')
    end
  end
end
