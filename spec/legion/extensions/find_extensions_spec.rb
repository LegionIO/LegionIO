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
    end

    context 'when Bundler is not defined' do
      it 'falls back to Gem::Specification.all_names' do
        hide_const('Bundler')
        allow(Gem::Specification).to receive(:all_names).and_return(['lex-fallback-0.1.0'])

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
