# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'

RSpec.describe 'Extension Registry wiring' do
  before { Legion::Registry.clear! }

  describe 'Legion::Extensions.register_in_registry' do
    context 'when Legion::Registry is defined' do
      it 'creates a Registry::Entry for a gem' do
        allow(Gem::Specification).to receive(:find_by_name).with('lex-example').and_return(
          instance_double(Gem::Specification, metadata: {})
        )

        Legion::Extensions.register_in_registry(gem_name: 'lex-example', version: '1.0.0')

        entry = Legion::Registry.lookup('lex-example')
        expect(entry).not_to be_nil
        expect(entry.name).to eq('lex-example')
        expect(entry.version).to eq('1.0.0')
        expect(entry.airb_status).to eq('approved')
        expect(entry.risk_tier).to eq('low')
      end

      it 'reads capabilities from gemspec metadata when available' do
        spec = instance_double(Gem::Specification, metadata: { 'legion.capabilities' => 'network:outbound, data:read' })
        allow(Gem::Specification).to receive(:find_by_name).with('lex-example').and_return(spec)

        Legion::Extensions.register_in_registry(gem_name: 'lex-example')

        entry = Legion::Registry.lookup('lex-example')
        expect(entry.capabilities).to eq(%w[network:outbound data:read])
      end

      it 'registers with empty capabilities when gemspec has no legion.capabilities key' do
        spec = instance_double(Gem::Specification, metadata: {})
        allow(Gem::Specification).to receive(:find_by_name).with('lex-example').and_return(spec)

        Legion::Extensions.register_in_registry(gem_name: 'lex-example')

        entry = Legion::Registry.lookup('lex-example')
        expect(entry.capabilities).to eq([])
      end

      it 'registers with empty capabilities when gem is not found' do
        allow(Gem::Specification).to receive(:find_by_name).with('lex-missing').and_raise(Gem::MissingSpecError.new('lex-missing', '>= 0'))

        Legion::Extensions.register_in_registry(gem_name: 'lex-missing')

        entry = Legion::Registry.lookup('lex-missing')
        expect(entry).not_to be_nil
        expect(entry.capabilities).to eq([])
      end

      it 'does not duplicate existing entries' do
        spec = instance_double(Gem::Specification, metadata: {})
        allow(Gem::Specification).to receive(:find_by_name).with('lex-example').and_return(spec)

        Legion::Extensions.register_in_registry(gem_name: 'lex-example', version: '1.0.0')
        Legion::Extensions.register_in_registry(gem_name: 'lex-example', version: '2.0.0')

        entry = Legion::Registry.lookup('lex-example')
        expect(entry.version).to eq('1.0.0')
      end
    end

    context 'when Legion::Registry is not defined' do
      it 'returns early without error' do
        hide_const('Legion::Registry')

        expect do
          Legion::Extensions.register_in_registry(gem_name: 'lex-example')
        end.not_to raise_error
      end
    end
  end
end
