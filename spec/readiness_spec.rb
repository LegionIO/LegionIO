# frozen_string_literal: true

require 'spec_helper'
require 'legion/readiness'

RSpec.describe Legion::Readiness do
  before { described_class.reset }
  after { described_class.reset }

  describe 'COMPONENTS' do
    it 'includes expected component symbols' do
      expect(described_class::COMPONENTS).to include(:settings, :crypt, :transport, :cache, :data, :extensions, :api)
    end

    it 'includes llm and rbac in COMPONENTS' do
      expect(described_class::COMPONENTS).to include(:llm, :rbac)
    end

    it 'is frozen' do
      expect(described_class::COMPONENTS).to be_frozen
    end
  end

  describe 'REQUIRED_COMPONENTS' do
    it 'includes core infrastructure components' do
      expect(described_class::REQUIRED_COMPONENTS).to include(:settings, :crypt, :transport, :cache, :data, :extensions, :api)
    end

    it 'does not include optional components' do
      expect(described_class::REQUIRED_COMPONENTS).not_to include(:rbac, :llm, :apollo, :gaia, :identity)
    end
  end

  describe 'OPTIONAL_COMPONENTS' do
    it 'includes optional components' do
      expect(described_class::OPTIONAL_COMPONENTS).to include(:rbac, :llm, :apollo, :gaia, :identity)
    end
  end

  describe 'DRAIN_TIMEOUT' do
    it 'is 5' do
      expect(described_class::DRAIN_TIMEOUT).to eq(5)
    end
  end

  describe '.mark_ready' do
    it 'marks a component as ready' do
      described_class.mark_ready(:settings)
      expect(described_class.ready?(:settings)).to eq(true)
    end
  end

  describe '.mark_not_ready' do
    it 'marks a component as not ready' do
      described_class.mark_ready(:settings)
      described_class.mark_not_ready(:settings)
      expect(described_class.ready?(:settings)).to eq(false)
    end
  end

  describe '.mark_skipped' do
    it 'marks a component as skipped' do
      described_class.mark_skipped(:rbac)
      expect(described_class.status[:rbac]).to eq(:skipped)
    end

    it 'counts as ready for individual component check' do
      described_class.mark_skipped(:rbac)
      expect(described_class.ready?(:rbac)).to eq(true)
    end

    it 'counts as ready for global readiness check' do
      described_class::COMPONENTS.each do |c|
        if described_class::OPTIONAL_COMPONENTS.include?(c)
          described_class.mark_skipped(c)
        else
          described_class.mark_ready(c)
        end
      end
      expect(described_class.ready?).to eq(true)
    end
  end

  describe '.ready?' do
    it 'returns false for unmarked components' do
      expect(described_class.ready?(:settings)).to eq(false)
    end

    it 'returns true when a specific component is marked ready' do
      described_class.mark_ready(:cache)
      expect(described_class.ready?(:cache)).to eq(true)
    end

    it 'returns false when called without args and not all components are ready' do
      described_class.mark_ready(:settings)
      expect(described_class.ready?).to eq(false)
    end

    it 'returns true when all components are ready' do
      described_class::COMPONENTS.each { |c| described_class.mark_ready(c) }
      expect(described_class.ready?).to eq(true)
    end

    it 'reports ready when optional llm is skipped' do
      described_class.reset
      described_class::COMPONENTS.each do |c|
        if c == :llm
          described_class.mark_skipped(c)
        else
          described_class.mark_ready(c)
        end
      end
      expect(described_class.ready?).to be true
    end

    it 'reports not ready when required component is missing' do
      described_class.reset
      described_class::COMPONENTS.each { |c| described_class.mark_ready(c) unless c == :settings }
      expect(described_class.ready?).to be false
    end
  end

  describe '.reset' do
    it 'clears all component status' do
      described_class.mark_ready(:settings)
      described_class.mark_ready(:cache)
      described_class.reset
      expect(described_class.ready?(:settings)).to eq(false)
      expect(described_class.ready?(:cache)).to eq(false)
    end
  end

  describe '.to_h' do
    it 'returns a hash with all components' do
      result = described_class.to_h
      expect(result).to be_a(Hash)
      described_class::COMPONENTS.each do |c|
        expect(result).to have_key(c)
      end
    end

    it 'returns boolean values' do
      described_class.mark_ready(:settings)
      result = described_class.to_h
      expect(result[:settings]).to eq(true)
      expect(result[:cache]).to eq(false)
    end

    it 'reports skipped components as true' do
      described_class.mark_skipped(:rbac)
      result = described_class.to_h
      expect(result[:rbac]).to eq(true)
    end
  end

  describe '.status' do
    it 'returns a hash' do
      expect(described_class.status).to be_a(Hash)
    end
  end

  describe '.wait_until_not_ready' do
    it 'returns immediately when components are already not ready' do
      start = Time.now
      described_class.wait_until_not_ready(:settings, timeout: 1)
      expect(Time.now - start).to be < 1
    end
  end
end
