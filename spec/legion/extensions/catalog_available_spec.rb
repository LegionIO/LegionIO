# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Catalog::Available do
  describe '.find' do
    it 'includes the Legion-native LLM hosted provider extensions' do
      expect(described_class.find('lex-llm-bedrock')).to include(
        name:     'lex-llm-bedrock',
        category: 'ai'
      )
      expect(described_class.find('lex-llm-azure-foundry')).to include(
        name:     'lex-llm-azure-foundry',
        category: 'ai'
      )
      expect(described_class.find('lex-llm-vertex')).to include(
        name:     'lex-llm-vertex',
        category: 'ai'
      )
    end
  end
end
