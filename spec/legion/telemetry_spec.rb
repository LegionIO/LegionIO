# frozen_string_literal: true

require 'spec_helper'
require 'legion/telemetry'

RSpec.describe Legion::Telemetry do
  describe '.enabled?' do
    it 'returns false when OTel SDK not loaded' do
      expect(described_class.enabled?).to be false
    end
  end

  describe '.with_span' do
    it 'yields nil when OTel not available' do
      result = described_class.with_span('test') { |span| span }
      expect(result).to be_nil
    end

    it 'returns block result when OTel not available' do
      result = described_class.with_span('test') { 42 }
      expect(result).to eq(42)
    end
  end

  describe '.sanitize_attributes' do
    it 'converts values to safe types' do
      attrs = described_class.sanitize_attributes({ name: 'test', count: 5, obj: Object.new })
      expect(attrs['name']).to eq('test')
      expect(attrs['count']).to eq(5)
      expect(attrs['obj']).to be_a(String)
    end

    it 'caps at max_keys' do
      large = (1..30).to_h { |i| ["key_#{i}", i] }
      attrs = described_class.sanitize_attributes(large, max_keys: 10)
      expect(attrs.size).to eq(10)
    end

    it 'handles nil input' do
      expect(described_class.sanitize_attributes(nil)).to eq({})
    end
  end
end
