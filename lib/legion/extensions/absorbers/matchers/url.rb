# frozen_string_literal: true

require 'uri'

module Legion
  module Extensions
    module Absorbers
      module Matchers
        class Url < Base
          def self.type = :url

          def self.match?(pattern, input)
            uri = parse_uri(input)
            return false unless uri

            host_pattern, path_pattern = split_pattern(pattern)
            return false unless host_matches?(host_pattern, uri.host)

            path_matches?(path_pattern || '**', uri.path)
          end

          class << self
            private

            def parse_uri(input)
              str = input.to_s.strip
              str = "https://#{str}" unless str.match?(%r{\A\w+://})
              uri = URI.parse(str)
              return nil unless uri.is_a?(URI::HTTP) && uri.host

              uri
            rescue URI::InvalidURIError
              nil
            end

            def split_pattern(pattern)
              clean = pattern.sub(%r{\A\w+://}, '')
              parts = clean.split('/', 2)
              [parts[0], parts[1]]
            end

            def host_matches?(pattern, host)
              return false unless host

              regex = Regexp.new(
                "\\A#{Regexp.escape(pattern).gsub('\\*', '[^.]+')}\\z",
                Regexp::IGNORECASE
              )
              regex.match?(host)
            end

            def path_matches?(pattern, path)
              path = path.to_s.sub(%r{\A/}, '')
              escaped = Regexp.escape(pattern)
                              .gsub('\\*\\*', '__.DOUBLE_STAR__.')
                              .gsub('\\*', '[^/]*')
                              .gsub('__.DOUBLE_STAR__.', '.*')
              Regexp.new("\\A#{escaped}\\z").match?(path)
            end
          end
        end
      end
    end
  end
end
