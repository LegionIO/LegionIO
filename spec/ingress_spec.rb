# frozen_string_literal: true

require 'spec_helper'
require 'legion/ingress'

# rubocop:disable Metrics/BlockLength
RSpec.describe Legion::Ingress do
  describe '.normalize' do
    it 'normalizes a hash payload' do
      result = described_class.normalize(payload: { key: 'value' })
      expect(result[:key]).to eq('value')
      expect(result[:source]).to eq('unknown')
      expect(result[:timestamp]).to be_a(Integer)
      expect(result[:datetime]).to be_a(String)
    end

    it 'normalizes a JSON string payload' do
      result = described_class.normalize(payload: '{"key":"value"}')
      expect(result[:key]).to eq('value')
    end

    it 'normalizes a nil payload' do
      result = described_class.normalize(payload: nil)
      expect(result).to be_a(Hash)
      expect(result[:source]).to eq('unknown')
    end

    it 'wraps non-hash non-string payloads' do
      result = described_class.normalize(payload: 42)
      expect(result[:value]).to eq(42)
    end

    it 'sets custom source' do
      result = described_class.normalize(payload: {}, source: 'http')
      expect(result[:source]).to eq('http')
    end

    it 'sets runner_class from parameter' do
      result = described_class.normalize(payload: {}, runner_class: 'MyRunner')
      expect(result[:runner_class]).to eq('MyRunner')
    end

    it 'sets function from parameter' do
      result = described_class.normalize(payload: {}, function: :fetch)
      expect(result[:function]).to eq(:fetch)
    end

    it 'keeps runner_class from payload when not given as param' do
      result = described_class.normalize(payload: { runner_class: 'FromPayload' })
      expect(result[:runner_class]).to eq('FromPayload')
    end

    it 'overrides payload runner_class with param' do
      result = described_class.normalize(payload: { runner_class: 'FromPayload' }, runner_class: 'FromParam')
      expect(result[:runner_class]).to eq('FromParam')
    end

    it 'merges extra opts into the result' do
      result = described_class.normalize(payload: {}, extra_key: 'extra_val')
      expect(result[:extra_key]).to eq('extra_val')
    end

    it 'symbolizes string keys from hash payload' do
      result = described_class.normalize(payload: { 'string_key' => 'val' })
      expect(result[:string_key]).to eq('val')
    end

    it 'preserves existing timestamp from payload' do
      result = described_class.normalize(payload: { timestamp: 1000 })
      expect(result[:timestamp]).to eq(1000)
    end
  end

  describe '.run' do
    it 'raises when runner_class is missing' do
      expect do
        described_class.run(payload: {}, function: :test)
      end.to raise_error(RuntimeError, 'runner_class is required')
    end

    it 'raises when function is missing' do
      expect do
        described_class.run(payload: {}, runner_class: 'TestRunner')
      end.to raise_error(RuntimeError, 'function is required')
    end
  end
end
# rubocop:enable Metrics/BlockLength
