# frozen_string_literal: true

require_relative 'teams_cache/sstable_reader'
require_relative 'teams_cache/record_parser'
require_relative 'teams_cache/extractor'

module Legion
  # Reads Microsoft Teams messages from the local Chromium IndexedDB cache.
  #
  # Teams 2.x (Edge WebView2) stores conversation data in LevelDB with Snappy
  # compression. This module provides a pure-Ruby reader that extracts messages
  # without requiring the Teams Graph API.
  #
  # Requires the `snappy` gem for block decompression.
  #
  # Usage:
  #   extractor = Legion::TeamsCache::Extractor.new
  #   messages = extractor.extract(skip_bots: true)
  #   messages.each { |m| puts "#{m.sender}: #{m.content}" }
  module TeamsCache
  end
end
