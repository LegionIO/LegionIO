# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/retry_policy'

RSpec.describe Legion::Extensions::Actors::RetryPolicy do
  around do |example|
    described_class.task_execution_settings
    original = Legion::Settings[:task_execution]
    Legion::Settings.loader.settings[:task_execution] = Legion::TaskExecution::Settings.default
    example.run
  ensure
    Legion::Settings.loader.settings[:task_execution] = original
  end

  it 'stops retries at the configured total attempt boundary' do
    Legion::Settings[:task_execution][:retry][:max_attempts] = 2
    expect(described_class.should_retry?(retry_count: 0, threshold: described_class.retry_threshold)).to be true
    expect(described_class.should_retry?(retry_count: 1, threshold: described_class.retry_threshold)).to be false
  end

  it 'caps exponential delay at the configured maximum' do
    Legion::Settings[:task_execution][:retry].merge!(base_delay_seconds: 2, max_delay_seconds: 5)
    expect(described_class.retry_delay(retry_count: 0)).to eq(2)
    expect(described_class.retry_delay(retry_count: 3)).to eq(5)
  end

  it 'rejects malformed and negative retry counts instead of resetting the budget' do
    expect { described_class.extract_retry_count(headers: { 'x-retry-count' => 'invalid' }) }.to raise_error(ArgumentError)
    expect { described_class.extract_retry_count(headers: { 'x-retry-count' => -1 }) }.to raise_error(ArgumentError)
  end
end
