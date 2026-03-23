# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'legion-data', path: '../legion-data' if File.exist?(File.expand_path('../legion-data', __dir__))
gem 'legion-gaia', path: '../legion-gaia' if File.exist?(File.expand_path('../legion-gaia', __dir__))
gem 'legion-llm', path: '../legion-llm' if File.exist?(File.expand_path('../legion-llm', __dir__))
gem 'legion-logging', path: '../legion-logging' if File.exist?(File.expand_path('../legion-logging', __dir__))
gem 'legion-mcp', path: '../legion-mcp' if File.exist?(File.expand_path('../legion-mcp', __dir__))

gem 'lex-llm-gateway', path: '../extensions-core/lex-llm-gateway'
gem 'lex-microsoft_teams', path: '../extensions/lex-microsoft_teams'

gem 'lex-agentic-memory', path: '../extensions-agentic/lex-agentic-memory'

gem 'pg'

gem 'kramdown', '>= 2.0'
gem 'mysql2'

group :test do
  gem 'graphql'
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'ruby_llm'
  gem 'simplecov'
end
