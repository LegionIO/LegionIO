# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Catalog do
  before { described_class.reset! }

  describe '.register' do
    it 'registers an extension with default state :registered' do
      described_class.register('lex-detect')
      expect(described_class.state('lex-detect')).to eq(:registered)
    end

    it 'accepts a custom initial state' do
      described_class.register('lex-detect', state: :loaded)
      expect(described_class.state('lex-detect')).to eq(:loaded)
    end

    it 'does not overwrite an existing entry' do
      described_class.register('lex-detect', state: :loaded)
      described_class.register('lex-detect', state: :registered)
      expect(described_class.state('lex-detect')).to eq(:loaded)
    end
  end

  describe '.transition' do
    before { described_class.register('lex-detect') }

    it 'transitions to a valid next state' do
      described_class.transition('lex-detect', :loaded)
      expect(described_class.state('lex-detect')).to eq(:loaded)
    end

    it 'updates started_at on transition to :running' do
      described_class.transition('lex-detect', :loaded)
      described_class.transition('lex-detect', :starting)
      described_class.transition('lex-detect', :running)
      entry = described_class.entry('lex-detect')
      expect(entry[:started_at]).to be_a(Time)
    end

    it 'publishes to transport when available' do
      allow(described_class).to receive(:publish_transition)
      described_class.transition('lex-detect', :loaded)
      expect(described_class).to have_received(:publish_transition).with('lex-detect', :loaded)
    end

    it 'persists to Data::Local when available' do
      allow(described_class).to receive(:persist_transition)
      described_class.transition('lex-detect', :loaded)
      expect(described_class).to have_received(:persist_transition).with('lex-detect', :loaded)
    end
  end

  describe '.loaded?' do
    it 'returns false for unregistered extensions' do
      expect(described_class.loaded?('lex-nonexistent')).to be false
    end

    it 'returns true when state is :loaded or beyond' do
      described_class.register('lex-detect', state: :loaded)
      expect(described_class.loaded?('lex-detect')).to be true
    end

    it 'returns false when state is :registered' do
      described_class.register('lex-detect')
      expect(described_class.loaded?('lex-detect')).to be false
    end
  end

  describe '.running?' do
    it 'returns true only when state is :running' do
      described_class.register('lex-detect', state: :running)
      expect(described_class.running?('lex-detect')).to be true
    end

    it 'returns false for :loaded' do
      described_class.register('lex-detect', state: :loaded)
      expect(described_class.running?('lex-detect')).to be false
    end
  end

  describe '.all' do
    it 'returns all registered extensions' do
      described_class.register('lex-detect')
      described_class.register('lex-node')
      expect(described_class.all.keys).to contain_exactly('lex-detect', 'lex-node')
    end
  end

  describe '.reset!' do
    it 'clears all entries' do
      described_class.register('lex-detect')
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end

  describe 'graceful degradation' do
    it 'does not raise when transport is unavailable' do
      described_class.register('lex-detect')
      expect { described_class.transition('lex-detect', :loaded) }.not_to raise_error
    end

    it 'does not raise when Data::Local is unavailable' do
      described_class.register('lex-detect')
      expect { described_class.transition('lex-detect', :loaded) }.not_to raise_error
    end
  end
end
