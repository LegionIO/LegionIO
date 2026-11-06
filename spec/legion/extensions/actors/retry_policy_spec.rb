# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/retry_policy'

RSpec.describe Legion::Extensions::Actors::RetryPolicy do
  it 'stops after two transport retries' do
    expect(described_class.should_retry?(retry_count: 0, threshold: described_class.retry_threshold)).to be true
    expect(described_class.should_retry?(retry_count: 1, threshold: described_class.retry_threshold)).to be true
    expect(described_class.should_retry?(retry_count: 2, threshold: described_class.retry_threshold)).to be false
  end

  it 'caps exponential delay at thirty seconds' do
    expect(described_class.retry_delay(retry_count: 0)).to eq(1)
    expect(described_class.retry_delay(retry_count: 1)).to eq(2)
    expect(described_class.retry_delay(retry_count: 5)).to eq(30)
  end

  it 'rejects malformed and negative retry counts instead of resetting the budget' do
    expect { described_class.extract_retry_count(headers: { 'x-retry-count' => 'invalid' }) }.to raise_error(ArgumentError)
    expect { described_class.extract_retry_count(headers: { 'x-retry-count' => -1 }) }.to raise_error(ArgumentError)
  end
end
