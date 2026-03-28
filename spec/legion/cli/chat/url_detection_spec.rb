# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/dispatch'

RSpec.describe 'Chat URL detection' do
  describe 'URL extraction from message' do
    it 'extracts URLs from a chat message' do
      urls = Legion::Extensions::Absorbers::Dispatch.extract_urls(
        'check out https://teams.microsoft.com/meeting/abc123 for the notes'
      )
      expect(urls).to include('https://teams.microsoft.com/meeting/abc123')
    end

    it 'extracts multiple URLs' do
      urls = Legion::Extensions::Absorbers::Dispatch.extract_urls(
        'see https://github.com/org/repo/pull/42 and https://example.com/doc.pdf'
      )
      expect(urls.size).to eq(2)
    end

    it 'returns empty array for no URLs' do
      urls = Legion::Extensions::Absorbers::Dispatch.extract_urls(
        'just a regular message about meetings'
      )
      expect(urls).to eq([])
    end
  end
end
