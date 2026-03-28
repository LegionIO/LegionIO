# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/matchers/file'

RSpec.describe Legion::Extensions::Absorbers::Matchers::File do
  describe '.match?' do
    it 'matches exact file extensions' do
      expect(described_class.match?('**/*.pdf', '/home/user/doc.pdf')).to be true
    end

    it 'matches nested paths' do
      expect(described_class.match?('**/*.docx', '/a/b/c/report.docx')).to be true
    end

    it 'rejects non-matching patterns' do
      expect(described_class.match?('**/*.pdf', '/home/user/doc.txt')).to be false
    end

    it 'matches absolute path patterns' do
      expect(described_class.match?('/home/user/docs/**/*', '/home/user/docs/report.pdf')).to be true
    end
  end

  describe '.type' do
    it 'returns :file' do
      expect(described_class.type).to eq(:file)
    end
  end
end
