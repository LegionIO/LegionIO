# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Core do
  describe '.trigger_words' do
    let(:ext_module) do
      Module.new do
        extend Legion::Extensions::Core
      end
    end

    it 'defaults to an empty array' do
      expect(ext_module.trigger_words).to eq([])
    end
  end
end
