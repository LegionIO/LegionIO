# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'

RSpec.describe Legion::Registry::Governance do
  before { described_class.reset! }

  describe '.config' do
    it 'returns defaults when Settings is not available' do
      expect(described_class.config).to eq(Legion::Registry::Governance::DEFAULTS)
    end

    it 'includes require_airb_approval defaulting to false' do
      expect(described_class.config[:require_airb_approval]).to be false
    end

    it 'includes auto_approve_risk_tiers with low' do
      expect(described_class.config[:auto_approve_risk_tiers]).to include('low')
    end

    it 'includes review_required_risk_tiers with medium, high, critical' do
      expect(described_class.config[:review_required_risk_tiers]).to include('medium', 'high', 'critical')
    end

    it 'includes naming_convention' do
      expect(described_class.config[:naming_convention]).to eq('lex-[a-z][a-z0-9_]*(?:-[a-z][a-z0-9_]*)*')
    end

    it 'includes deprecation_notice_days defaulting to 30' do
      expect(described_class.config[:deprecation_notice_days]).to eq(30)
    end
  end

  describe '.check_name' do
    it 'accepts valid lex names' do
      expect(described_class.check_name('lex-http')).to be true
    end

    it 'accepts names with digits and underscores after the first character' do
      expect(described_class.check_name('lex-my_ext2')).to be true
    end

    it 'accepts nested lex extension names' do
      expect(described_class.check_name('lex-llm-openai')).to be true
      expect(described_class.check_name('lex-llm-azure-foundry')).to be true
    end

    it 'rejects names not matching convention' do
      expect(described_class.check_name('bad-name')).to be false
    end

    it 'rejects uppercase names' do
      expect(described_class.check_name('lex-HTTP')).to be false
    end

    it 'rejects names with no suffix' do
      expect(described_class.check_name('lex-')).to be false
    end

    it 'rejects empty string' do
      expect(described_class.check_name('')).to be false
    end
  end

  describe '.auto_approve?' do
    it 'returns true for low tier' do
      expect(described_class.auto_approve?('low')).to be true
    end

    it 'returns false for high tier' do
      expect(described_class.auto_approve?('high')).to be false
    end

    it 'returns false for medium tier' do
      expect(described_class.auto_approve?('medium')).to be false
    end

    it 'returns false for critical tier' do
      expect(described_class.auto_approve?('critical')).to be false
    end
  end

  describe '.review_required?' do
    it 'returns true for medium tier' do
      expect(described_class.review_required?('medium')).to be true
    end

    it 'returns true for high tier' do
      expect(described_class.review_required?('high')).to be true
    end

    it 'returns true for critical tier' do
      expect(described_class.review_required?('critical')).to be true
    end

    it 'returns false for low tier' do
      expect(described_class.review_required?('low')).to be false
    end
  end

  describe '.reset!' do
    it 'clears memoized config' do
      described_class.config
      described_class.reset!
      expect(described_class.instance_variable_get(:@config)).to be_nil
    end
  end

  describe 'Registry.register naming enforcement' do
    before { Legion::Registry.clear! }

    it 'raises ArgumentError for a name that violates naming convention' do
      entry = Legion::Registry::Entry.new(name: 'invalid_name', risk_tier: 'low')
      expect { Legion::Registry.register(entry) }.to raise_error(ArgumentError, /violates naming convention/)
    end

    it 'accepts a valid lex name' do
      entry = Legion::Registry::Entry.new(name: 'lex-valid', risk_tier: 'low')
      expect { Legion::Registry.register(entry) }.not_to raise_error
    end

    it 'auto-approves low risk tier entries on register' do
      entry = Legion::Registry::Entry.new(name: 'lex-autoapp', risk_tier: 'low')
      Legion::Registry.register(entry)
      stored = Legion::Registry.lookup('lex-autoapp')
      expect(stored.airb_status).to eq('approved')
      expect(stored.status).to eq(:approved)
    end

    it 'does not auto-approve high risk tier entries on register' do
      entry = Legion::Registry::Entry.new(name: 'lex-hightest', risk_tier: 'high')
      Legion::Registry.register(entry)
      stored = Legion::Registry.lookup('lex-hightest')
      expect(stored.airb_status).to eq('pending')
    end
  end
end
