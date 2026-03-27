# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/matchers/base'
require 'legion/extensions/absorbers/matchers/url'

RSpec.describe Legion::Extensions::Absorbers::Matchers::Url do
  describe '.type' do
    it 'returns :url' do
      expect(described_class.type).to eq(:url)
    end
  end

  describe '.match?' do
    it 'matches exact host and wildcard path' do
      expect(described_class.match?(
               'teams.microsoft.com/l/meetup-join/*',
               'https://teams.microsoft.com/l/meetup-join/abc123'
             )).to be true
    end

    it 'matches wildcard subdomain' do
      expect(described_class.match?(
               '*.sharepoint.com/sites/*/Documents/*',
               'https://contoso.sharepoint.com/sites/team/Documents/report.docx'
             )).to be true
    end

    it 'rejects non-matching hosts' do
      expect(described_class.match?(
               'teams.microsoft.com/l/meetup-join/*',
               'https://zoom.us/j/123456'
             )).to be false
    end

    it 'rejects non-matching paths' do
      expect(described_class.match?(
               'teams.microsoft.com/l/meetup-join/*',
               'https://teams.microsoft.com/l/channel/abc'
             )).to be false
    end

    it 'handles URLs without scheme' do
      expect(described_class.match?(
               'teams.microsoft.com/l/meetup-join/*',
               'teams.microsoft.com/l/meetup-join/abc123'
             )).to be true
    end

    it 'returns false for non-URL input' do
      expect(described_class.match?(
               'teams.microsoft.com/*',
               'this is not a url'
             )).to be false
    end

    it 'matches double-star glob for deep paths' do
      expect(described_class.match?(
               'github.com/**/issues/*',
               'https://github.com/LegionIO/LegionIO/issues/42'
             )).to be true
    end
  end

  describe '.registered?' do
    it 'is registered in the matcher registry' do
      expect(Legion::Extensions::Absorbers::Matchers::Base.for_type(:url)).to eq(described_class)
    end
  end
end
