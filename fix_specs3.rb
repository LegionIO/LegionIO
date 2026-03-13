#!/usr/bin/env ruby
# frozen_string_literal: true

Dir.glob('spec/api/*_spec.rb').each do |f|
  content = File.read(f)

  # Fix remaining mixed string access on nested symbol hashes
  content.gsub!(/body\[:(\w+)\]\['(\w+)'\]/) { "body[:#{Regexp.last_match(1)}][:#{Regexp.last_match(2)}]" }

  # Fix Legion::JSON.dump with keyword args (remaining ones)
  content.gsub!(/Legion::JSON\.dump\((\w+: )/) { "Legion::JSON.dump({#{Regexp.last_match(1)}" }
  # Make sure we close the hash properly
  content.gsub!(/Legion::JSON\.dump\(\{([^}]+)\),/) { "Legion::JSON.dump({#{Regexp.last_match(1)}})," }

  File.write(f, content)
  puts "Fixed: #{f}"
end
