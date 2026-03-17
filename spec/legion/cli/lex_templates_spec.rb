# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/lex_templates'

RSpec.describe Legion::CLI::LexTemplates do
  describe '.list' do
    it 'returns all templates' do
      templates = described_class.list
      expect(templates.size).to eq(5)
      expect(templates.map { |t| t[:name] }).to include('basic', 'llm-agent')
    end
  end

  describe '.get' do
    it 'returns template config' do
      config = described_class.get('llm-agent')
      expect(config[:runners]).to include('processor', 'analyzer')
      expect(config[:client]).to be true
    end

    it 'returns nil for unknown' do
      expect(described_class.get('nonexistent')).to be_nil
    end
  end

  describe '.valid?' do
    it 'validates known templates' do
      expect(described_class.valid?('basic')).to be true
      expect(described_class.valid?('fake')).to be false
    end
  end
end
