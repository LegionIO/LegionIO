# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/retry_policy'

RSpec.describe 'Subscription retry integration' do
  describe 'message lifecycle with threshold=2' do
    it 'allows 2 retries then dead-letters' do
      threshold = 2
      headers = {}

      # First failure: retry_count=0, should retry
      count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      expect(count).to eq(0)
      expect(Legion::Extensions::Actors::RetryPolicy.should_retry?(retry_count: count, threshold: threshold)).to be true

      # After republish: retry_count=1, should retry
      headers = { 'x-retry-count' => 1 }
      count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      expect(count).to eq(1)
      expect(Legion::Extensions::Actors::RetryPolicy.should_retry?(retry_count: count, threshold: threshold)).to be true

      # After second republish: retry_count=2, should dead-letter
      headers = { 'x-retry-count' => 2 }
      count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      expect(count).to eq(2)
      expect(Legion::Extensions::Actors::RetryPolicy.should_retry?(retry_count: count, threshold: threshold)).to be false
    end
  end

  describe 'configurable threshold' do
    it 'respects custom threshold from settings' do
      allow(Legion::Settings).to receive(:dig).with(:fleet, :poison_message_threshold).and_return(5)
      allow(Legion::Settings).to receive(:dig).with(:transport, :retry_threshold).and_return(nil)

      expect(Legion::Extensions::Actors::RetryPolicy.retry_threshold).to eq(5)

      headers = { 'x-retry-count' => 4 }
      count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      expect(Legion::Extensions::Actors::RetryPolicy.should_retry?(retry_count: count, threshold: 5)).to be true

      headers = { 'x-retry-count' => 5 }
      count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      expect(Legion::Extensions::Actors::RetryPolicy.should_retry?(retry_count: count, threshold: 5)).to be false
    end
  end
end
