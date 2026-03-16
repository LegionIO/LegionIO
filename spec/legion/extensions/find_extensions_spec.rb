# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  describe '.find_extensions' do
    before do
      described_class.instance_variable_set(:@extensions, nil)
      allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
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
end
