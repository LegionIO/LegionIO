# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/entity_extract'

RSpec.describe Legion::CLI::Chat::Tools::EntityExtract do
  subject(:tool) { described_class.new }

  let(:extractor_mod) do
    Module.new do
      def extract_entities(text:, entity_types: nil, min_confidence: 0.7, **) # rubocop:disable Lint/UnusedMethodArgument
        entities = [
          { name: 'Alice', type: 'person', confidence: 0.95 },
          { name: 'LegionIO', type: 'service', confidence: 0.88 }
        ]
        types = Array(entity_types)
        entities.select! { |e| types.include?(e[:type]) } unless types.empty?
        entities.select! { |e| e[:confidence] >= min_confidence }
        { success: true, entities: entities, source: :llm }
      end
    end
  end

  before do
    stub_const('Legion::Extensions::Apollo::Runners::EntityExtractor', extractor_mod)
  end

  describe '#execute' do
    it 'returns extracted entities' do
      result = tool.execute(text: 'Alice works on LegionIO')
      expect(result).to include('Extracted 2 entities')
      expect(result).to include('Alice')
      expect(result).to include('LegionIO')
    end

    it 'filters by entity type' do
      result = tool.execute(text: 'Alice works on LegionIO', entity_types: 'person')
      expect(result).to include('Alice')
      expect(result).not_to include('LegionIO')
    end

    it 'returns unavailable when extractor not loaded' do
      hide_const('Legion::Extensions::Apollo::Runners::EntityExtractor')
      result = tool.execute(text: 'test')
      expect(result).to eq('Apollo entity extractor not available.')
    end

    it 'returns no entities message when none found' do
      empty_mod = Module.new do
        def extract_entities(**)
          { success: true, entities: [], source: :llm }
        end
      end
      stub_const('Legion::Extensions::Apollo::Runners::EntityExtractor', empty_mod)
      result = tool.execute(text: 'nothing here', min_confidence: 0.99)
      expect(result).to eq('No entities found in the provided text.')
    end

    it 'shows confidence percentages' do
      result = tool.execute(text: 'Alice')
      expect(result).to include('95%')
    end
  end
end
