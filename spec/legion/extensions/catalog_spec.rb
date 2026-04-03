# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Catalog do
  before do
    described_class.reset!
    allow(Legion::Logging).to receive(:warn)
  end

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

    it 'publishes a raw catalog event instead of using function-backed dynamic messages' do
      exchange = instance_double('Legion::Transport::Exchange', publish: true)
      exchange_class = class_double('Legion::Transport::Exchange', new: exchange)
      connection = class_double('Legion::Transport::Connection', session_open?: true)
      stub_const('Legion::Transport::Exchange', exchange_class)
      stub_const('Legion::Transport::Connection', connection)

      allow(described_class).to receive(:persist_transition)

      described_class.transition('lex-detect', :loaded)

      expect(exchange_class).to have_received(:new).with('legion.catalog')
      expect(exchange).to have_received(:publish).with(
        kind_of(String),
        routing_key:  'legion.catalog.lex-detect.loaded',
        content_type: 'application/json',
        persistent:   true
      )
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

    it 'warns once and skips persistence when extension_catalog is missing' do
      connection = double('Sequel::Database', tables: [])
      local = Module.new do
        class << self
          attr_accessor :connection
        end

        def self.connected? = true
        def self.registered_migrations = {}
      end
      local.connection = connection
      allow(local).to receive(:register_migrations)
      stub_const('Legion::Data::Local', local)

      described_class.register('lex-detect')
      described_class.transition('lex-detect', :loaded)
      described_class.transition('lex-detect', :running)
      described_class.flush_persisted_transitions

      expect(local).to have_received(:register_migrations).with(
        name: :extension_catalog,
        path: kind_of(String)
      ).at_least(:once)
      expect(Legion::Logging).to have_received(:warn).with(/extension_catalog table is missing/).once
    end

    it 'registers the local migration lazily once Data::Local is available' do
      connection = double('Sequel::Database', tables: [:extension_catalog])
      dataset = instance_double('Sequel::Dataset', first: nil)
      model = double('Sequel::Model', where: dataset, insert: true)
      nil
      local = Module.new do
        class << self
          attr_accessor :connection
        end

        def self.connected? = true
        def self.registered_migrations = {}
      end
      local.connection = connection
      allow(connection).to receive(:transaction) { |&blk| blk.call }
      allow(local).to receive(:register_migrations)
      allow(local).to receive(:model).with(:extension_catalog).and_return(model)
      stub_const('Legion::Data::Local', local)

      described_class.register('lex-detect')
      described_class.transition('lex-detect', :loaded)
      described_class.flush_persisted_transitions

      expect(local).to have_received(:register_migrations).with(
        name: :extension_catalog,
        path: kind_of(String)
      )
    end
  end
end
