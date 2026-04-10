# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Tools::TriggerIndex do
  before { described_class.clear }

  let(:tool_a) do
    Class.new(Legion::Tools::Base) do
      tool_name 'legion-github-pr-create'
      trigger_words %w[git github pr]
    end
  end

  let(:tool_b) do
    Class.new(Legion::Tools::Base) do
      tool_name 'legion-vault-secrets-read'
      trigger_words %w[vault secret]
    end
  end

  describe '.build_from_registry' do
    before do
      Legion::Tools::Registry.clear
      Legion::Tools::Registry.register(tool_a)
      Legion::Tools::Registry.register(tool_b)
      described_class.build_from_registry
    end

    it 'indexes trigger words to tool classes' do
      matched, _per_word = described_class.match(Set['git'])
      expect(matched).to include(tool_a)
      expect(matched).not_to include(tool_b)
    end

    it 'returns tools for multiple matched words' do
      matched, _per_word = described_class.match(Set['git', 'vault'])
      expect(matched).to include(tool_a, tool_b)
    end

    it 'returns empty set for no matches' do
      matched, _per_word = described_class.match(Set['unknown'])
      expect(matched).to be_empty
    end

    it 'returns per_word breakdown for scoring' do
      _matched, per_word = described_class.match(Set['git', 'vault'])
      expect(per_word).to have_key('git')
      expect(per_word).to have_key('vault')
      expect(per_word['git']).to include(tool_a)
    end

    it 'handles overlapping trigger words across tools' do
      tool_c = Class.new(Legion::Tools::Base) do
        tool_name 'legion-github-repos-list'
        trigger_words %w[git repo]
      end
      Legion::Tools::Registry.register(tool_c)
      described_class.build_from_registry

      matched, _per_word = described_class.match(Set['git'])
      expect(matched).to include(tool_a, tool_c)
      expect(matched).not_to include(tool_b)
    end
  end

  describe '.match' do
    it 'returns empty set when index is empty' do
      matched, per_word = described_class.match(Set['anything'])
      expect(matched).to be_empty
      expect(per_word).to be_empty
    end
  end

  describe '.empty?' do
    it 'is true when no trigger words are indexed' do
      expect(described_class).to be_empty
    end

    it 'is false after building from registry with trigger words' do
      Legion::Tools::Registry.clear
      Legion::Tools::Registry.register(tool_a)
      described_class.build_from_registry
      expect(described_class).not_to be_empty
    end
  end

  describe '.size' do
    it 'returns the number of unique trigger words indexed' do
      Legion::Tools::Registry.clear
      Legion::Tools::Registry.register(tool_a)
      Legion::Tools::Registry.register(tool_b)
      described_class.build_from_registry
      expect(described_class.size).to eq(5) # git, github, pr, vault, secret
    end
  end
end
