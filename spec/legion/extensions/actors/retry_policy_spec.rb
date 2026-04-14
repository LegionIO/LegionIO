# frozen_string_literal: true

require 'spec_helper'

# Load just the module we are testing
require 'legion/extensions/actors/retry_policy'

RSpec.describe Legion::Extensions::Actors::RetryPolicy do
  describe '.should_retry?' do
    context 'with default threshold of 2' do
      it 'returns true when retry count is 0' do
        expect(described_class.should_retry?(retry_count: 0, threshold: 2)).to be true
      end

      it 'returns true when retry count is 1' do
        expect(described_class.should_retry?(retry_count: 1, threshold: 2)).to be true
      end

      it 'returns false when retry count equals threshold' do
        expect(described_class.should_retry?(retry_count: 2, threshold: 2)).to be false
      end

      it 'returns false when retry count exceeds threshold' do
        expect(described_class.should_retry?(retry_count: 5, threshold: 2)).to be false
      end
    end

    context 'with threshold of 0 (no retries)' do
      it 'returns false immediately' do
        expect(described_class.should_retry?(retry_count: 0, threshold: 0)).to be false
      end
    end

    context 'with nil threshold (unlimited retries)' do
      it 'always returns true' do
        expect(described_class.should_retry?(retry_count: 100, threshold: nil)).to be true
      end
    end
  end

  describe '.extract_retry_count' do
    it 'returns 0 when no headers present' do
      expect(described_class.extract_retry_count(nil)).to eq(0)
    end

    it 'returns 0 when x-retry-count header is missing' do
      expect(described_class.extract_retry_count({})).to eq(0)
    end

    it 'reads x-retry-count from headers' do
      headers = { 'x-retry-count' => 3 }
      expect(described_class.extract_retry_count(headers)).to eq(3)
    end

    it 'handles symbol keys' do
      headers = { :'x-retry-count' => 2 }
      expect(described_class.extract_retry_count(headers)).to eq(2)
    end
  end

  describe '.retry_threshold' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:fleet, :poison_message_threshold).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:transport, :retry_threshold).and_return(nil)
    end

    it 'returns 2 as the default' do
      expect(described_class.retry_threshold).to eq(2)
    end

    it 'reads from fleet settings when available' do
      allow(Legion::Settings).to receive(:dig).with(:fleet, :poison_message_threshold).and_return(5)
      expect(described_class.retry_threshold).to eq(5)
    end

    it 'reads from transport settings as fallback' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :retry_threshold).and_return(3)
      expect(described_class.retry_threshold).to eq(3)
    end
  end
end
