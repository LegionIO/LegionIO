# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Identity::Trust do
  describe '.levels' do
    it 'returns all trust levels in descending order of trust' do
      expect(described_class.levels).to eq(%i[verified authenticated configured cached unverified])
    end
  end

  describe '.rank' do
    it 'returns 0 for :verified (highest trust)' do
      expect(described_class.rank(:verified)).to eq(0)
    end

    it 'returns 4 for :unverified (lowest trust)' do
      expect(described_class.rank(:unverified)).to eq(4)
    end

    it 'returns nil for unknown levels' do
      expect(described_class.rank(:bogus)).to be_nil
    end
  end

  describe '.above?' do
    it 'returns true when first level is more trusted' do
      expect(described_class.above?(:verified, :cached)).to be true
    end

    it 'returns false when first level is less trusted' do
      expect(described_class.above?(:unverified, :verified)).to be false
    end

    it 'returns false when levels are equal' do
      expect(described_class.above?(:verified, :verified)).to be false
    end
  end

  describe '.at_least?' do
    it 'returns true when levels are equal' do
      expect(described_class.at_least?(:verified, :verified)).to be true
    end

    it 'returns true when first is more trusted' do
      expect(described_class.at_least?(:verified, :cached)).to be true
    end

    it 'returns false when first is less trusted' do
      expect(described_class.at_least?(:unverified, :verified)).to be false
    end
  end
end
