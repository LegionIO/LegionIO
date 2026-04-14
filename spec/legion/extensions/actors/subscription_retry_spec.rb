# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/retry_policy'

RSpec.describe 'Subscription retry behavior' do
  let(:queue) { double('queue') }
  let(:delivery_info) { double('delivery_info', delivery_tag: 'tag-1') }

  describe 'reject_or_retry logic' do
    # Test the decision logic extracted into a helper method
    # that the subscription actor will call

    it 'requeues when under threshold' do
      headers = { 'x-retry-count' => 0 }
      retry_count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      threshold = 2

      should_retry = Legion::Extensions::Actors::RetryPolicy.should_retry?(
        retry_count: retry_count, threshold: threshold
      )

      expect(should_retry).to be true
      # In the actor: queue.reject(tag, requeue: true) with incremented header
    end

    it 'dead-letters when at threshold' do
      headers = { 'x-retry-count' => 2 }
      retry_count = Legion::Extensions::Actors::RetryPolicy.extract_retry_count(headers)
      threshold = 2

      should_retry = Legion::Extensions::Actors::RetryPolicy.should_retry?(
        retry_count: retry_count, threshold: threshold
      )

      expect(should_retry).to be false
      # In the actor: queue.reject(tag, requeue: false) -> DLX
    end
  end
end
