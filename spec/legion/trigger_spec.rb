# frozen_string_literal: true

require 'spec_helper'
require 'legion/trigger'

RSpec.describe Legion::Trigger do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
    allow(Legion::Logging).to receive(:error)
  end

  describe '.source_for' do
    it 'returns a Github adapter' do
      expect(described_class.source_for('github')).to be_a(Legion::Trigger::Sources::Github)
    end

    it 'returns a Slack adapter' do
      expect(described_class.source_for('slack')).to be_a(Legion::Trigger::Sources::Slack)
    end

    it 'returns a Linear adapter' do
      expect(described_class.source_for('linear')).to be_a(Legion::Trigger::Sources::Linear)
    end

    it 'raises for unknown source' do
      expect { described_class.source_for('unknown') }.to raise_error(ArgumentError, /unknown trigger source/)
    end
  end

  describe '.registered_sources' do
    it 'includes github, slack, linear' do
      expect(described_class.registered_sources).to contain_exactly('github', 'slack', 'linear')
    end
  end

  describe '.process' do
    let(:headers) do
      { 'HTTP_X_GITHUB_EVENT' => 'push', 'HTTP_X_GITHUB_DELIVERY' => 'del-1' }
    end
    let(:body) { { 'ref' => 'refs/heads/main' } }
    let(:body_raw) { '{"ref":"refs/heads/main"}' }

    before do
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:trigger, :sources, anything, :require_verified).and_return(false)
      # Ensure no cache interference from other tests
      hide_const('Legion::Cache') if defined?(Legion::Cache)
    end

    it 'returns success when AMQP is not available (bridge skipped)' do
      result = described_class.process(
        source_name: 'github', headers: headers, body_raw: body_raw, body: body
      )
      expect(result[:success]).to be true
      expect(result[:routing_key]).to eq('trigger.github.push')
      expect(result[:correlation_id]).to start_with('leg-')
    end

    it 'returns error for unknown source' do
      result = described_class.process(
        source_name: 'bogus', headers: {}, body_raw: '', body: {}
      )
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:unknown_source)
    end

    it 'detects duplicates via cache' do
      stub_const('Legion::Cache', Module.new do
        @seen = {}

        def self.respond_to?(name, *)
          %i[get set].include?(name) || super
        end

        def self.get(key)
          @seen[key]
        end

        def self.set(key, val, ttl: nil) # rubocop:disable Lint/UnusedMethodArgument
          @seen[key] = val
        end
      end)

      # First call succeeds
      result1 = described_class.process(
        source_name: 'github', headers: headers, body_raw: body_raw, body: body
      )
      expect(result1[:success]).to be true

      # Second call with same delivery_id is duplicate
      result2 = described_class.process(
        source_name: 'github', headers: headers, body_raw: body_raw, body: body
      )
      expect(result2[:success]).to be false
      expect(result2[:reason]).to eq(:duplicate)
    end
  end
end
