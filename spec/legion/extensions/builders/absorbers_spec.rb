# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Builders::Absorbers' do
  let(:builder_module) { Legion::Extensions::Builder::Absorbers }

  it 'is defined' do
    expect(builder_module).to be_a(Module)
  end

  describe '#build_absorbers' do
    it 'responds to build_absorbers when included' do
      dummy = Module.new { extend Legion::Extensions::Builder::Absorbers }
      expect(dummy).to respond_to(:build_absorbers)
    end
  end

  describe '#absorbers' do
    it 'returns empty hash by default' do
      dummy = Module.new { extend Legion::Extensions::Builder::Absorbers }
      expect(dummy.absorbers).to eq({})
    end
  end
end
