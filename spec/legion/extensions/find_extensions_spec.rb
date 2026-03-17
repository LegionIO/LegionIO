# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  describe '.find_extensions' do
    before do
      described_class.instance_variable_set(:@extensions, nil)
      allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
      allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: nil })
    end

    context 'when running under Bundler' do
      it 'uses Bundler.load.specs instead of Gem::Specification.all_names' do
        fake_spec = double('spec', name: 'lex-fake', version: '0.1.0')
        fake_bundler_load = double('bundler_load', specs: [fake_spec])
        allow(Bundler).to receive(:load).and_return(fake_bundler_load)

        described_class.find_extensions

        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions).to have_key('fake')
        expect(extensions['fake'][:gem_name]).to eq('lex-fake')
      end

      it 'correctly parses multi-hyphenated gem names' do
        fake_spec = double('spec', name: 'lex-cognitive-reappraisal', version: '0.1.0')
        fake_bundler_load = double('bundler_load', specs: [fake_spec])
        allow(Bundler).to receive(:load).and_return(fake_bundler_load)

        described_class.find_extensions

        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions).to have_key('cognitive_reappraisal')
        expect(extensions['cognitive_reappraisal'][:gem_name]).to eq('lex-cognitive-reappraisal')
        expect(extensions['cognitive_reappraisal'][:version]).to eq('0.1.0')
        expect(extensions['cognitive_reappraisal'][:extension_class]).to eq('Legion::Extensions::CognitiveReappraisal')
      end
    end

    context 'when Bundler is not defined' do
      it 'falls back to Gem::Specification.latest_specs' do
        hide_const('Bundler')
        fake_spec = double('spec', name: 'lex-fallback', version: double(to_s: '0.1.0'))
        allow(Gem::Specification).to receive(:latest_specs).and_return([fake_spec])

        described_class.find_extensions

        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions).to have_key('fallback')
      end
    end

    it 'uses start_with? for lex- prefix matching' do
      fake_spec = double('spec', name: 'not-a-lex', version: '1.0.0')
      fake_spec2 = double('spec', name: 'lex-real', version: '0.2.0')
      fake_bundler_load = double('bundler_load', specs: [fake_spec, fake_spec2])
      allow(Bundler).to receive(:load).and_return(fake_bundler_load)

      described_class.find_extensions

      extensions = described_class.instance_variable_get(:@extensions)
      expect(extensions).not_to have_key('not')
      expect(extensions).to have_key('real')
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
    before do
      described_class.instance_variable_set(:@extensions, {
                                              'node'      => { gem_name: 'lex-node', extension_name: 'node' },
                                              'tasker'    => { gem_name: 'lex-tasker', extension_name: 'tasker' },
                                              'health'    => { gem_name: 'lex-health', extension_name: 'health' },
                                              'attention' => { gem_name: 'lex-attention', extension_name: 'attention' },
                                              'memory'    => { gem_name: 'lex-memory', extension_name: 'memory' },
                                              'claude'    => { gem_name: 'lex-claude', extension_name: 'claude' },
                                              'github'    => { gem_name: 'lex-github', extension_name: 'github' },
                                              'slack'     => { gem_name: 'lex-slack', extension_name: 'slack' }
                                            })
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
        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions.keys).to include('node', 'tasker', 'health')
        expect(extensions.keys).not_to include('attention', 'slack')
      end
    end

    context 'when profile is :custom' do
      it 'only loads listed extensions' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({
                                                                         profile:    'custom',
                                                                         extensions: %w[node github]
                                                                       })
        described_class.send(:apply_role_filter)
        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions.keys).to match_array(%w[node github])
      end
    end

    context 'when profile is :dev' do
      it 'loads core + ai + essential agentic' do
        allow(Legion::Settings).to receive(:[]).with(:role).and_return({ profile: 'dev' })
        described_class.send(:apply_role_filter)
        extensions = described_class.instance_variable_get(:@extensions)
        expect(extensions.keys).to include('node', 'memory', 'claude')
        expect(extensions.keys).not_to include('slack', 'github')
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
