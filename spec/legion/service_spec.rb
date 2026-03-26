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
end
