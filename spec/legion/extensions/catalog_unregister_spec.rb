# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Catalog unregister on extension unload' do
  describe '.unregister_capabilities' do
    it 'is a no-op (replaced by Tools::Registry.clear on reload)' do
      expect { Legion::Extensions.unregister_capabilities('lex-github') }.not_to raise_error
    end
  end
end
