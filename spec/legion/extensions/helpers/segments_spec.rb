# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Segments do
  describe '.derive_segments' do
    it 'returns single-element array for flat gem' do
      expect(described_class.derive_segments('lex-node')).to eq(['node'])
    end

    it 'preserves underscores within a segment' do
      expect(described_class.derive_segments('lex-microsoft_teams')).to eq(['microsoft_teams'])
    end

    it 'splits dashes into separate segments' do
      expect(described_class.derive_segments('lex-agentic-cognitive-anchor')).to eq(%w[agentic cognitive anchor])
    end

    it 'handles dashes and underscores together' do
      expect(described_class.derive_segments('lex-agentic-attention_spotlight')).to eq(%w[agentic attention_spotlight])
    end

    it 'handles deep nesting' do
      expect(described_class.derive_segments('lex-agentic-cognitive-dissonance-resolution'))
        .to eq(%w[agentic cognitive dissonance resolution])
    end
  end

  describe '.derive_namespace' do
    it 'capitalizes a single flat segment' do
      expect(described_class.derive_namespace('lex-node')).to eq(['Node'])
    end

    it 'converts underscored segment to CamelCase' do
      expect(described_class.derive_namespace('lex-microsoft_teams')).to eq(['MicrosoftTeams'])
    end

    it 'maps dashes to separate capitalized namespace parts' do
      expect(described_class.derive_namespace('lex-agentic-cognitive-anchor')).to eq(%w[Agentic Cognitive Anchor])
    end

    it 'handles underscores within a nested segment' do
      expect(described_class.derive_namespace('lex-agentic-attention_spotlight')).to eq(%w[Agentic AttentionSpotlight])
    end
  end

  describe '.derive_const_path' do
    it 'returns flat Legion::Extensions::Name for single segment' do
      expect(described_class.derive_const_path('lex-node'))
        .to eq('Legion::Extensions::Node')
    end

    it 'returns fully nested path for multi-segment gem' do
      expect(described_class.derive_const_path('lex-agentic-cognitive-anchor'))
        .to eq('Legion::Extensions::Agentic::Cognitive::Anchor')
    end

    it 'handles underscored segments' do
      expect(described_class.derive_const_path('lex-microsoft_teams'))
        .to eq('Legion::Extensions::MicrosoftTeams')
    end
  end

  describe '.derive_require_path' do
    it 'returns flat path for single segment' do
      expect(described_class.derive_require_path('lex-node'))
        .to eq('legion/extensions/node')
    end

    it 'returns nested path for multi-segment gem' do
      expect(described_class.derive_require_path('lex-agentic-cognitive-anchor'))
        .to eq('legion/extensions/agentic/cognitive/anchor')
    end

    it 'preserves underscores in path segments' do
      expect(described_class.derive_require_path('lex-microsoft_teams'))
        .to eq('legion/extensions/microsoft_teams')
    end
  end

  describe '.segments_to_log_tag' do
    it 'wraps each segment in brackets' do
      expect(described_class.segments_to_log_tag(%w[agentic cognitive anchor]))
        .to eq('[agentic][cognitive][anchor]')
    end

    it 'handles single segment' do
      expect(described_class.segments_to_log_tag(['node'])).to eq('[node]')
    end
  end

  describe '.segments_to_amqp_prefix' do
    it 'prepends legion. and joins with dots' do
      expect(described_class.segments_to_amqp_prefix(%w[agentic cognitive anchor]))
        .to eq('legion.agentic.cognitive.anchor')
    end

    it 'handles single segment' do
      expect(described_class.segments_to_amqp_prefix(['node'])).to eq('legion.node')
    end
  end

  describe '.segments_to_settings_path' do
    it 'converts strings to symbols' do
      expect(described_class.segments_to_settings_path(%w[agentic cognitive anchor]))
        .to eq(%i[agentic cognitive anchor])
    end
  end

  describe '.segments_to_table_prefix' do
    it 'joins with underscores' do
      expect(described_class.segments_to_table_prefix(%w[agentic cognitive anchor]))
        .to eq('agentic_cognitive_anchor')
    end

    it 'handles single segment' do
      expect(described_class.segments_to_table_prefix(['node'])).to eq('node')
    end
  end

  describe '.categorize_gem' do
    let(:categories) do
      {
        core:    { type: :list, tier: 1 },
        ai:      { type: :list, tier: 2 },
        gaia:    { type: :list, tier: 3 },
        agentic: { type: :prefix, tier: 4 }
      }
    end
    let(:lists) { { core: %w[lex-node lex-tasker], ai: %w[lex-claude], gaia: %w[lex-tick] } }

    it 'identifies a core gem by list membership' do
      result = described_class.categorize_gem('lex-node', categories: categories, lists: lists)
      expect(result).to eq({ category: :core, tier: 1 })
    end

    it 'identifies an agentic gem by prefix' do
      result = described_class.categorize_gem('lex-agentic-cognitive-anchor', categories: categories, lists: lists)
      expect(result).to eq({ category: :agentic, tier: 4 })
    end

    it 'returns tier 5 default for uncategorized gems' do
      result = described_class.categorize_gem('lex-consul', categories: categories, lists: lists)
      expect(result).to eq({ category: :default, tier: 5 })
    end

    it 'list membership takes priority over prefix matching' do
      # lex-core-thing would match prefix 'core' but core is a :list type not :prefix
      # A gem in the lists hash takes priority
      result = described_class.categorize_gem('lex-node', categories: categories, lists: lists)
      expect(result[:category]).to eq(:core)
    end
  end
end
