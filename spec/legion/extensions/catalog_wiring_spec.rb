# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Extension Catalog wiring' do
  before { Legion::Extensions::Catalog.reset! }

  describe 'lifecycle state transitions' do
    it 'registers extensions during discovery' do
      Legion::Extensions::Catalog.register('lex-test')
      expect(Legion::Extensions::Catalog.state('lex-test')).to eq(:registered)
    end

    it 'transitions to :loaded after successful load' do
      Legion::Extensions::Catalog.register('lex-test')
      Legion::Extensions::Catalog.transition('lex-test', :loaded)
      expect(Legion::Extensions::Catalog.loaded?('lex-test')).to be true
    end

    it 'transitions through starting to running' do
      Legion::Extensions::Catalog.register('lex-test', state: :loaded)
      Legion::Extensions::Catalog.transition('lex-test', :starting)
      Legion::Extensions::Catalog.transition('lex-test', :running)
      expect(Legion::Extensions::Catalog.running?('lex-test')).to be true
    end

    it 'transitions through stopping to stopped' do
      Legion::Extensions::Catalog.register('lex-test', state: :running)
      Legion::Extensions::Catalog.transition('lex-test', :stopping)
      Legion::Extensions::Catalog.transition('lex-test', :stopped)
      expect(Legion::Extensions::Catalog.state('lex-test')).to eq(:stopped)
    end
  end
end
