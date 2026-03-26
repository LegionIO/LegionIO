# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'

RSpec.describe Legion::Service do
  describe '#setup_generated_functions' do
    let(:service) { described_class.allocate }

    it 'calls GeneratedRegistry.load_on_boot when codegen is available' do
      stub_const('Legion::Extensions::Codegen::Helpers::GeneratedRegistry', Module.new do
        def self.load_on_boot
          0
        end
      end)
      expect(Legion::Extensions::Codegen::Helpers::GeneratedRegistry).to receive(:load_on_boot).and_return(0)
      service.send(:setup_generated_functions)
    end

    it 'does nothing when codegen is not loaded' do
      expect { service.send(:setup_generated_functions) }.not_to raise_error
    end
  end
end
