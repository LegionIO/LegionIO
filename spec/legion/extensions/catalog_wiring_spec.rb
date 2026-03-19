# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Extension Catalog wiring' do
  before { Legion::Extensions::Catalog.reset! }

  describe 'load_extensions integration' do
    it 'registers extensions during discovery' do
      Legion::Extensions::Catalog.register('lex-test')
      expect(Legion::Extensions::Catalog.state('lex-test')).to eq(:registered)
    end

    it 'transitions to :loaded after successful gem_load' do
      Legion::Extensions::Catalog.register('lex-test')
      Legion::Extensions::Catalog.transition('lex-test', :loaded)
      expect(Legion::Extensions::Catalog.loaded?('lex-test')).to be true
    end

    it 'transitions to :running when actors are hooked' do
      Legion::Extensions::Catalog.register('lex-test', state: :loaded)
      Legion::Extensions::Catalog.transition('lex-test', :starting)
      Legion::Extensions::Catalog.transition('lex-test', :running)
      expect(Legion::Extensions::Catalog.running?('lex-test')).to be true
    end
  end
end
