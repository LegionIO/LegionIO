# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  describe '.find_extensions' do
    let(:mock_specs) do
      [
        { name: 'lex-node', version: '0.1.0' },
        { name: 'lex-agentic-cognitive-anchor', version: '0.1.0' },
        { name: 'lex-claude',                  version: '0.1.0' },
        { name: 'lex-consul',                  version: '0.1.0' }
      ]
    end

    before do
      described_class.instance_variable_set(:@extensions, nil)
      allow(described_class).to receive(:gem_names_for_discovery).and_return(mock_specs)
      allow(Legion::Settings).to receive(:[]).with(:extensions).and_return(
        core: %w[lex-node], ai: %w[lex-claude], gaia: [],
        categories: {
          core:    { type: :list, tier: 1 },
          ai:      { type: :list, tier: 2 },
          gaia:    { type: :list, tier: 3 },
          agentic: { type: :prefix, tier: 4 }
        },
        blocked: [], agentic: { allowed: nil, blocked: [] }
      )
      allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: nil })
    end

    it 'returns an array of entry hashes' do
      result = described_class.find_extensions
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it 'each entry has required keys' do
      result = described_class.find_extensions
      entry = result.first
      expect(entry).to include(:gem_name, :category, :tier, :segments, :const_path, :require_path)
    end

    it 'returns extensions in tier order (core before ai before agentic before default)' do
      result = described_class.find_extensions
      names = result.map { |e| e[:gem_name] }
      expect(names.index('lex-node')).to be < names.index('lex-claude')
      expect(names.index('lex-claude')).to be < names.index('lex-agentic-cognitive-anchor')
      expect(names.index('lex-agentic-cognitive-anchor')).to be < names.index('lex-consul')
    end

    it 'only includes lex-* gems, excluding non-lex gems' do
      allow(described_class).to receive(:gem_names_for_discovery).and_return(
        [{ name: 'not-a-lex', version: '1.0.0' }, { name: 'lex-real', version: '0.2.0' }]
      )
      result = described_class.find_extensions
      gem_names = result.map { |e| e[:gem_name] }
      expect(gem_names).not_to include('not-a-lex')
      expect(gem_names).to include('lex-real')
    end

    it 'includes lex-node entry' do
      result = described_class.find_extensions
      gem_names = result.map { |e| e[:gem_name] }
      expect(gem_names).to include('lex-node')
    end

    it 'includes lex-agentic-cognitive-anchor entry' do
      result = described_class.find_extensions
      gem_names = result.map { |e| e[:gem_name] }
      expect(gem_names).to include('lex-agentic-cognitive-anchor')
    end

    context 'when running under Bundler' do
      it 'uses Bundler.load.specs for discovery' do
        fake_spec = double('spec', name: 'lex-fake', version: '0.1.0')
        fake_bundler_load = double('bundler_load', specs: [fake_spec])
        allow(described_class).to receive(:gem_names_for_discovery).and_call_original
        allow(Bundler).to receive(:load).and_return(fake_bundler_load)

        described_class.instance_variable_set(:@extensions, nil)
        described_class.find_extensions

        extensions = described_class.instance_variable_get(:@extensions)
        gem_names = extensions.map { |e| e[:gem_name] }
        expect(gem_names).to include('lex-fake')
      end
    end

    context 'when Bundler is not defined' do
      it 'falls back to Gem::Specification.latest_specs' do
        hide_const('Bundler')
        fake_spec = double('spec', name: 'lex-fallback', version: double(to_s: '0.1.0'))
        allow(Gem::Specification).to receive(:latest_specs).and_return([fake_spec])
        allow(described_class).to receive(:gem_names_for_discovery).and_call_original

        described_class.instance_variable_set(:@extensions, nil)
        described_class.find_extensions

        extensions = described_class.instance_variable_get(:@extensions)
        gem_names = extensions.map { |e| e[:gem_name] }
        expect(gem_names).to include('lex-fallback')
      end
    end
  end

  describe '.ensure_namespace' do
    it 'creates intermediate modules for nested const path' do
      described_class.ensure_namespace('Legion::Extensions::Agentic::Cognitive::TestEnsure')
      expect(Legion::Extensions::Agentic).to be_a(Module)
      expect(Legion::Extensions::Agentic::Cognitive).to be_a(Module)
    end

    it 'does NOT create the final constant (TestEnsure itself)' do
      described_class.ensure_namespace('Legion::Extensions::Agentic::Cognitive::TestEnsureLeaf')
      expect(Legion::Extensions::Agentic::Cognitive.const_defined?(:TestEnsureLeaf, false)).to be false
    end

    it 'is idempotent — calling twice does not raise' do
      expect do
        described_class.ensure_namespace('Legion::Extensions::Agentic::Cognitive::TestEnsure')
        described_class.ensure_namespace('Legion::Extensions::Agentic::Cognitive::TestEnsure')
      end.not_to raise_error
    end

    it 'does nothing for flat extensions (no intermediate modules needed)' do
      expect { described_class.ensure_namespace('Legion::Extensions::Node') }.not_to raise_error
    end

    it 'does nothing for two-segment paths (Legion::Extensions::X has no intermediates)' do
      expect { described_class.ensure_namespace('Legion::Extensions::SomeThing') }.not_to raise_error
    end
  end

  describe '.categorize_and_order' do
    let(:gem_names) do
      %w[
        lex-consul lex-node lex-agentic-cognitive-anchor lex-claude
        lex-tick lex-tasker lex-agentic-attention-spotlight lex-slack
        lex-openai lex-apollo
      ]
    end

    let(:ext_settings) do
      {
        core:       %w[lex-node lex-tasker],
        ai:         %w[lex-claude lex-openai],
        gaia:       %w[lex-tick lex-apollo],
        categories: {
          core:    { type: :list, tier: 1 },
          ai:      { type: :list, tier: 2 },
          gaia:    { type: :list, tier: 3 },
          agentic: { type: :prefix, tier: 4 }
        },
        blocked:    ['lex-slack'],
        agentic:    { allowed: nil, blocked: [] }
      }
    end

    before do
      allow(Legion::Settings).to receive(:[]).with(:extensions).and_return(ext_settings)
    end

    it 'returns gems in tier order' do
      result = described_class.categorize_and_order(gem_names)
      names = result.map { |r| r[:gem_name] }
      expect(names.index('lex-node')).to be < names.index('lex-claude')
      expect(names.index('lex-claude')).to be < names.index('lex-tick')
      expect(names.index('lex-tick')).to be < names.index('lex-agentic-cognitive-anchor')
      expect(names.index('lex-agentic-cognitive-anchor')).to be < names.index('lex-consul')
    end

    it 'excludes blocked gems' do
      result = described_class.categorize_and_order(gem_names)
      expect(result.map { |r| r[:gem_name] }).not_to include('lex-slack')
    end

    it 'skips list gems that are not in the input' do
      result = described_class.categorize_and_order(['lex-node'])
      names = result.map { |r| r[:gem_name] }
      expect(names).to eq(['lex-node'])
    end

    it 'assigns correct categories' do
      result = described_class.categorize_and_order(gem_names)
      by_name = result.to_h { |r| [r[:gem_name], r] }
      expect(by_name['lex-node'][:category]).to eq(:core)
      expect(by_name['lex-claude'][:category]).to eq(:ai)
      expect(by_name['lex-tick'][:category]).to eq(:gaia)
      expect(by_name['lex-agentic-cognitive-anchor'][:category]).to eq(:agentic)
      expect(by_name['lex-consul'][:category]).to eq(:default)
    end

    it 'derives nested const_path for agentic gems' do
      result = described_class.categorize_and_order(gem_names)
      anchor = result.find { |r| r[:gem_name] == 'lex-agentic-cognitive-anchor' }
      expect(anchor[:const_path]).to eq('Legion::Extensions::Agentic::Cognitive::Anchor')
    end

    it 'derives flat const_path for list-category gems' do
      result = described_class.categorize_and_order(gem_names)
      node = result.find { |r| r[:gem_name] == 'lex-node' }
      expect(node[:const_path]).to eq('Legion::Extensions::Node')
    end

    it 'derives flat const_path for default-tier gems' do
      result = described_class.categorize_and_order(gem_names)
      consul = result.find { |r| r[:gem_name] == 'lex-consul' }
      expect(consul[:const_path]).to eq('Legion::Extensions::Consul')
    end

    it 'each entry includes gem_name, category, tier, segments, const_path, require_path' do
      result = described_class.categorize_and_order(['lex-node'])
      entry = result.first
      expect(entry).to include(:gem_name, :category, :tier, :segments, :const_path, :require_path)
    end
  end

  describe '.check_reserved_words' do
    it 'warns when an unknown-origin gem uses a reserved category prefix' do
      expect(Legion::Logging).to receive(:warn).with(/reserved prefix/)
      described_class.check_reserved_words('lex-agentic-custom-thing', known_org: false)
    end

    it 'does not warn for known org gems' do
      expect(Legion::Logging).not_to receive(:warn)
      described_class.check_reserved_words('lex-agentic-cognitive-anchor', known_org: true)
    end

    it 'warns when first segment is a reserved word' do
      expect(Legion::Logging).to receive(:warn).with(/reserved word/)
      described_class.check_reserved_words('lex-transport-adapter', known_org: false)
    end

    it 'does not raise, just warns' do
      expect { described_class.check_reserved_words('lex-transport-adapter', known_org: false) }.not_to raise_error
    end
  end

  describe '.apply_role_filter' do
    # @extensions is now an array of entry hashes, each with :gem_name
    def build_entry(gem_name, category, tier)
      segments = gem_name.delete_prefix('lex-').split('-')
      {
        gem_name:     gem_name,
        category:     category,
        tier:         tier,
        segments:     segments,
        const_path:   "Legion::Extensions::#{segments.map(&:capitalize).join('::')}",
        require_path: "legion/extensions/#{segments.join('/')}"
      }
    end

    let(:sample_entries) do
      [
        build_entry('lex-node',      :core,    1),
        build_entry('lex-tasker',    :core,    1),
        build_entry('lex-health',    :core,    1),
        build_entry('lex-attention', :default, 5),
        build_entry('lex-memory',    :default, 5),
        build_entry('lex-claude',    :ai,      2),
        build_entry('lex-github',    :default, 5),
        build_entry('lex-slack',     :default, 5)
      ]
    end

    before do
      described_class.instance_variable_set(:@extensions, sample_entries.dup)
    end

    def ext_gem_names
      described_class.instance_variable_get(:@extensions).map { |e| e[:gem_name] }
    end

    context 'when profile is nil' do
      it 'loads all extensions' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: nil })
        described_class.send(:apply_role_filter)
        expect(described_class.instance_variable_get(:@extensions).count).to eq(8)
      end
    end

    context 'when profile is :core' do
      it 'only loads core extensions' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: 'core' })
        described_class.send(:apply_role_filter)
        names = ext_gem_names
        expect(names).to include('lex-node', 'lex-tasker', 'lex-health')
        expect(names).not_to include('lex-attention', 'lex-slack')
      end
    end

    context 'when profile is :custom' do
      it 'only loads listed extensions' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({
                                                                         profile:    'custom',
                                                                         extensions: %w[node github]
                                                                       })
        described_class.send(:apply_role_filter)
        expect(ext_gem_names).to match_array(%w[lex-node lex-github])
      end
    end

    context 'when profile is :dev' do
      it 'loads core + ai + essential agentic' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: 'dev' })
        described_class.send(:apply_role_filter)
        names = ext_gem_names
        expect(names).to include('lex-node', 'lex-memory', 'lex-claude')
        expect(names).not_to include('lex-slack', 'lex-github')
      end
    end

    context 'when profile is unknown' do
      it 'loads all extensions' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: 'unknown_thing' })
        described_class.send(:apply_role_filter)
        expect(described_class.instance_variable_get(:@extensions).count).to eq(8)
      end
    end
  end
end
