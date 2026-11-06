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
        identity_phase = phases.find { |num, _| num == 0 }
        expect(identity_phase).not_to be_nil
        names = identity_phase.last.map { |e| e[:gem_name] }
        expect(names).to contain_exactly('lex-identity-kerberos', 'lex-identity-ldap', 'lex-identity-system')
      end

      it 'groups non-identity extensions into phase 1' do
        phases = described_class.send(:group_by_phase)
        main_phase = phases.find { |num, _| num == 1 }
        expect(main_phase).not_to be_nil
        names = main_phase.last.map { |e| e[:gem_name] }
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
        identity_phase = phases.find { |num, _| num == 0 }
        expect(identity_phase).to be_nil
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

  describe '.hook_extensions' do
    let(:lex_llm) { { gem_name: 'lex-llm', category: :default, tier: 5 } }
    let(:lex_llm_openai) { { gem_name: 'lex-llm-openai', category: :default, tier: 5 } }
    let(:lex_llm_ollama) { { gem_name: 'lex-llm-ollama', category: :default, tier: 5 } }
    let(:lex_http) { { gem_name: 'lex-http', category: :core, tier: 1 } }
    let(:lex_identity) { { gem_name: 'lex-identity-system', category: :identity, tier: 0 } }

    before do
      allow(described_class).to receive(:find_extensions)
      allow(described_class).to receive(:transition_loaded_extensions)
      allow(described_class).to receive(:load_yaml_agents)
      allow(described_class).to receive(:reset_runtime_handles!)
      allow(Legion::Extensions::Catalog).to receive(:flush_persisted_transitions)
    end

    it 'loads lex-llm before lex-llm provider extensions and normal phases' do
      phases = [
        [0, [lex_identity]],
        [1, [lex_llm_openai, lex_http, lex_llm, lex_llm_ollama]]
      ]
      loaded_phases = []

      allow(described_class).to receive(:group_by_phase).and_return(phases)
      allow(described_class).to receive(:load_phase_extensions) do |phase_name, entries|
        loaded_phases << [phase_name, entries.map { |entry| entry[:gem_name] }]
      end
      allow(described_class).to receive(:hook_phase_actors)

      described_class.hook_extensions

      expect(loaded_phases).to eq(
        [
          [0, ['lex-identity-system']],
          [:llm_base, ['lex-llm']],
          [:llm_extensions, %w[lex-llm-ollama lex-llm-openai]],
          [1, ['lex-http']]
        ]
      )
    end

    it 'keeps normal phase loading unchanged when no lex-llm gems are discovered' do
      phases = [
        [0, [lex_identity]],
        [1, [lex_http]]
      ]
      loaded_phases = []

      allow(described_class).to receive(:group_by_phase).and_return(phases)
      allow(described_class).to receive(:load_phase_extensions) do |phase_name, entries|
        loaded_phases << [phase_name, entries.map { |entry| entry[:gem_name] }]
      end
      allow(described_class).to receive(:hook_phase_actors)

      described_class.hook_extensions

      expect(loaded_phases).to eq(
        [
          [0, ['lex-identity-system']],
          [1, ['lex-http']]
        ]
      )
    end

    it 'loads lex-llm before providers discovered through Bundler' do
      phases = [
        [1, [lex_llm_openai, lex_http, lex_llm, lex_llm_ollama]]
      ]
      loaded_names = []

      allow(described_class).to receive(:group_by_phase).and_return(phases)
      allow(described_class).to receive(:load_phase_extensions) do |_phase_name, entries|
        loaded_names.concat(entries.map { |entry| entry[:gem_name] })
      end
      allow(described_class).to receive(:hook_phase_actors)

      described_class.hook_extensions

      expect(loaded_names.index('lex-llm')).to be < loaded_names.index('lex-llm-openai')
      expect(loaded_names.index('lex-llm')).to be < loaded_names.index('lex-llm-ollama')
    end
  end

  describe '.require_identity_extensions' do
    let(:lex_identity) do
      {
        gem_name:      'lex-identity-system',
        category:      :identity,
        tier:          0,
        segments:      %w[identity system],
        const_path:    'Legion::Extensions::Identity::System',
        require_path:  'legion/extensions/identity/system',
        settings_path: %i[identity system]
      }
    end
    let(:lex_http) do
      {
        gem_name:      'lex-http',
        category:      :core,
        tier:          1,
        segments:      ['http'],
        const_path:    'Legion::Extensions::Http',
        require_path:  'legion/extensions/http',
        settings_path: [:http]
      }
    end

    before do
      allow(described_class).to receive(:find_extensions).and_return([lex_identity, lex_http])
      allow(described_class).to receive(:extension_settings_for_entry).and_return({})
      allow(described_class).to receive(:latest_installed_version)
      allow(described_class).to receive(:register_extension_handle)
      allow(described_class).to receive(:ensure_namespace)
      allow(described_class).to receive(:gem_load)
      allow(Legion::Extensions::Catalog).to receive(:register)
    end

    it 'requires identity extension files without loading non-identity extensions' do
      described_class.require_identity_extensions

      expect(described_class).to have_received(:gem_load).with(lex_identity)
      expect(described_class).not_to have_received(:gem_load).with(lex_http)
    end

    it 'does not require disabled identity extensions' do
      allow(described_class).to receive(:extension_settings_for_entry).with(lex_identity).and_return(enabled: false)
      allow(described_class).to receive(:extension_settings_for_entry).with(lex_http).and_return({})

      described_class.require_identity_extensions

      expect(described_class).not_to have_received(:gem_load)
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
      non_identity = registry.except(:identity)
      non_identity.each_value do |v|
        expect(v[:phase]).to eq(1), "Expected phase 1 for #{v}"
      end
    end
  end
end
