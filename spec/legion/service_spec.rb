# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'

RSpec.describe Legion::Service do
  describe '#setup_generated_functions' do
    subject(:service) { described_class.allocate }

    context 'when GeneratedRegistry is defined' do
      before do
        registry = Module.new do
          def self.load_on_boot
            3
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'calls load_on_boot' do
        expect(Legion::Extensions::Codegen::Helpers::GeneratedRegistry).to receive(:load_on_boot).and_return(3)
        service.setup_generated_functions
      end

      it 'returns without error when load_on_boot returns zero' do
        allow(Legion::Extensions::Codegen::Helpers::GeneratedRegistry).to receive(:load_on_boot).and_return(0)
        expect { service.setup_generated_functions }.not_to raise_error
      end
    end

    context 'when GeneratedRegistry is not defined' do
      before { hide_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry') }

      it 'returns without error' do
        expect { service.setup_generated_functions }.not_to raise_error
      end
    end

    context 'when load_on_boot raises an error' do
      before do
        registry = Module.new do
          def self.load_on_boot
            raise StandardError, 'database unavailable'
          end
        end
        stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', registry)
      end

      it 'rescues the error and does not propagate' do
        expect { service.setup_generated_functions }.not_to raise_error
      end
    end
  end

  describe '#find_identity_providers' do
    subject(:service) { described_class.allocate }

    let(:top_level_provider) do
      Module.new do
        def self.resolve = { id: '1', canonical_name: 'top' }
        def self.provider_name = :top_level
      end
    end

    let(:nested_provider) do
      Module.new do
        def self.resolve = { id: '2', canonical_name: 'nested' }
        def self.provider_name = :nested
      end
    end

    context 'when Legion::Extensions is not defined' do
      before { hide_const('Legion::Extensions') }

      it 'returns an empty array' do
        expect(service.send(:find_identity_providers)).to eq([])
      end
    end

    context 'when no extensions respond to resolve and provider_name' do
      before { stub_const('Legion::Extensions', Module.new) }

      it 'returns an empty array' do
        expect(service.send(:find_identity_providers)).to eq([])
      end
    end

    context 'when a top-level extension is a valid provider' do
      before do
        provider = top_level_provider
        ext_ns = Module.new { const_set(:TopProvider, provider) }
        stub_const('Legion::Extensions', ext_ns)
      end

      it 'discovers the top-level provider' do
        providers = service.send(:find_identity_providers)
        expect(providers.length).to eq(1)
        expect(providers.first.provider_name).to eq(:top_level)
      end
    end

    context 'when a provider is nested inside a sub-namespace' do
      before do
        provider = nested_provider
        inner_ns = Module.new { const_set(:Kerberos, provider) }
        outer_ns = Module.new { const_set(:Identity, inner_ns) }
        stub_const('Legion::Extensions', outer_ns)
      end

      it 'discovers the nested provider recursively' do
        providers = service.send(:find_identity_providers)
        expect(providers.length).to eq(1)
        expect(providers.first.provider_name).to eq(:nested)
      end
    end

    context 'when providers exist at multiple nesting levels' do
      before do
        top    = top_level_provider
        nested = nested_provider
        inner_ns = Module.new { const_set(:Sub, nested) }
        outer_ns = Module.new do
          const_set(:TopProvider, top)
          const_set(:Inner, inner_ns)
        end
        stub_const('Legion::Extensions', outer_ns)
      end

      it 'discovers providers at all levels' do
        providers = service.send(:find_identity_providers)
        expect(providers.length).to eq(2)
        expect(providers.map(&:provider_name)).to contain_exactly(:top_level, :nested)
      end
    end

    context 'when a constant raises during traversal' do
      before do
        bad_ns = Module.new do
          def self.constants(*)
            [:BadConst]
          end

          def self.const_get(name, *)
            raise StandardError, 'load error' if name == :BadConst

            super
          end
        end
        stub_const('Legion::Extensions', bad_ns)
      end

      it 'skips the bad constant and returns an empty array' do
        expect { service.send(:find_identity_providers) }.not_to raise_error
        expect(service.send(:find_identity_providers)).to eq([])
      end
    end

    context 'when circular module references exist' do
      before do
        mod_a = Module.new
        mod_b = Module.new
        mod_a.const_set(:B, mod_b)
        mod_b.const_set(:A, mod_a)
        stub_const('Legion::Extensions', mod_a)
      end

      it 'handles cycles without infinite recursion' do
        expect { service.send(:find_identity_providers) }.not_to raise_error
      end
    end
  end
end
