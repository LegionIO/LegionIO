# frozen_string_literal: true

require 'spec_helper'
require 'legion/compliance'

RSpec.describe Legion::Compliance do
  before do
    described_class.setup
  end

  describe '.setup' do
    it 'registers compliance defaults' do
      expect(Legion::Settings.dig(:compliance, :enabled)).to eq(true)
    end
  end

  describe '.enabled?' do
    it 'returns true by default' do
      expect(described_class.enabled?).to be true
    end
  end

  describe '.phi_enabled?' do
    it 'returns true by default' do
      expect(described_class.phi_enabled?).to be true
    end
  end

  describe '.pci_enabled?' do
    it 'returns true by default' do
      expect(described_class.pci_enabled?).to be true
    end
  end

  describe '.pii_enabled?' do
    it 'returns true by default' do
      expect(described_class.pii_enabled?).to be true
    end
  end

  describe '.fedramp_enabled?' do
    it 'returns true by default' do
      expect(described_class.fedramp_enabled?).to be true
    end
  end

  describe '.classification_level' do
    it 'returns confidential by default' do
      expect(described_class.classification_level).to eq('confidential')
    end
  end

  describe '.profile' do
    it 'returns a hash with all compliance flags' do
      profile = described_class.profile
      expect(profile[:classification_level]).to eq('confidential')
      expect(profile[:phi]).to be true
      expect(profile[:pci]).to be true
      expect(profile[:pii]).to be true
      expect(profile[:fedramp]).to be true
      expect(profile[:log_redaction]).to be true
      expect(profile[:cache_phi_max_ttl]).to eq(3600)
    end
  end
end
