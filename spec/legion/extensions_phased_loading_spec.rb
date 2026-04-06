# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:warn)
    allow(Legion::Logging).to receive(:debug)
  end

  describe '.group_by_phase' do
    before do
      described_class.instance_variable_set(:@extensions, extensions)
    end

    after do
      described_class.instance_variable_set(:@extensions, nil)
    end

    context 'with identity and default extensions' do
      let(:extensions) do
        [
          { gem_name: 'lex-identity-kerberos', category: :identity, tier: 0 },
          { gem_name: 'lex-identity-ldap',     category: :identity, tier: 0 },
          { gem_name: 'lex-identity-system',   category: :identity, tier: 0 },
          { gem_name: 'lex-http',              category: :core,     tier: 1 },
          { gem_name: 'lex-redis',             category: :core,     tier: 1 },
          { gem_name: 'lex-agentic-memory',    category: :agentic,  tier: 4 }
        ]
      end

      it 'groups identity extensions into phase 0' do
        phases = described_class.send(:group_by_phase)
        phase_0 = phases.find { |num, _| num == 0 }
        expect(phase_0).not_to be_nil
        names = phase_0.last.map { |e| e[:gem_name] }
        expect(names).to contain_exactly('lex-identity-kerberos', 'lex-identity-ldap', 'lex-identity-system')
      end

      it 'groups non-identity extensions into phase 1' do
        phases = described_class.send(:group_by_phase)
        phase_1 = phases.find { |num, _| num == 1 }
        expect(phase_1).not_to be_nil
        names = phase_1.last.map { |e| e[:gem_name] }
        expect(names).to contain_exactly('lex-http', 'lex-redis', 'lex-agentic-memory')
      end

      it 'returns phases sorted by phase number (0 before 1)' do
        phases = described_class.send(:group_by_phase)
        expect(phases.map(&:first)).to eq([0, 1])
      end
    end

    context 'with no identity extensions' do
      let(:extensions) do
        [
          { gem_name: 'lex-http',  category: :core, tier: 1 },
          { gem_name: 'lex-redis', category: :core, tier: 1 }
        ]
      end

      it 'has no phase 0' do
        phases = described_class.send(:group_by_phase)
        phase_0 = phases.find { |num, _| num == 0 }
        expect(phase_0).to be_nil
      end

      it 'puts everything in phase 1' do
        phases = described_class.send(:group_by_phase)
        expect(phases.size).to eq(1)
        expect(phases.first.first).to eq(1)
      end
    end

    context 'with default category extensions' do
      let(:extensions) do
        [
          { gem_name: 'lex-custom-thing', category: :default, tier: 5 }
        ]
      end

      it 'assigns default category to phase 1' do
        phases = described_class.send(:group_by_phase)
        expect(phases.first.first).to eq(1)
      end
    end
  end

  describe '.default_category_registry' do
    subject(:registry) { described_class.send(:default_category_registry) }

    it 'includes identity category at phase 0' do
      expect(registry[:identity][:phase]).to eq(0)
    end

    it 'includes identity category with prefix type' do
      expect(registry[:identity][:type]).to eq(:prefix)
    end

    it 'includes identity category at tier 0' do
      expect(registry[:identity][:tier]).to eq(0)
    end

    it 'assigns all other categories to phase 1' do
      non_identity = registry.reject { |k, _| k == :identity }
      non_identity.each_value do |v|
        expect(v[:phase]).to eq(1), "Expected phase 1 for #{v}"
      end
    end
  end
end
