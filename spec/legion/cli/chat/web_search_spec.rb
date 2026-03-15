# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/web_search'

RSpec.describe Legion::CLI::Chat::WebSearch do
  describe '.parse_duckduckgo_results' do
    let(:html) do
      <<~HTML
        <div class="results">
          <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fruby">Ruby Programming</a>
          <a class="result__snippet" href="#">Ruby is a dynamic language</a>
          <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fruby-lang.org">Ruby Language</a>
          <a class="result__snippet" href="#">Official Ruby website</a>
          <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fgithub.com%2Fruby">Ruby on GitHub</a>
          <a class="result__snippet" href="#">Ruby source code</a>
        </div>
      HTML
    end

    it 'parses results with titles and URLs' do
      results = described_class.parse_duckduckgo_results(html, 5)
      expect(results.length).to eq(3)
      expect(results.first[:title]).to eq('Ruby Programming')
      expect(results.first[:url]).to eq('https://example.com/ruby')
    end

    it 'includes snippets' do
      results = described_class.parse_duckduckgo_results(html, 5)
      expect(results.first[:snippet]).to eq('Ruby is a dynamic language')
    end

    it 'respects max_results' do
      results = described_class.parse_duckduckgo_results(html, 2)
      expect(results.length).to eq(2)
    end

    it 'returns empty array for no results' do
      results = described_class.parse_duckduckgo_results('<html></html>', 5)
      expect(results).to eq([])
    end
  end

  describe '.extract_real_url' do
    it 'extracts URL from DuckDuckGo redirect' do
      ddg = 'https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpage'
      expect(described_class.extract_real_url(ddg)).to eq('https://example.com/page')
    end

    it 'returns direct URL unchanged' do
      expect(described_class.extract_real_url('https://example.com')).to eq('https://example.com')
    end
  end

  describe '.strip_tags' do
    it 'removes HTML tags' do
      expect(described_class.strip_tags('<b>bold</b> text')).to eq('bold text')
    end

    it 'decodes HTML entities' do
      expect(described_class.strip_tags('A &amp; B')).to eq('A & B')
    end
  end

  describe '.search' do
    it 'raises SearchError on connection failure' do
      allow(Net::HTTP).to receive(:new).and_raise(SocketError, 'getaddrinfo failed')
      expect { described_class.search('test') }.to raise_error(described_class::SearchError, /Connection failed/)
    end
  end
end
