# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'legion-data', path: '../legion-data' if File.exist?(File.expand_path('../legion-data', __dir__))
gem 'legion-gaia', path: '../legion-gaia' if File.exist?(File.expand_path('../legion-gaia', __dir__))
gem 'legion-llm', path: '../legion-llm' if File.exist?(File.expand_path('../legion-llm', __dir__))
gem 'legion-logging', path: '../legion-logging' if File.exist?(File.expand_path('../legion-logging', __dir__))
gem 'legion-mcp', path: '../legion-mcp' if File.exist?(File.expand_path('../legion-mcp', __dir__))
gem 'legion-settings', path: '../legion-settings' if File.exist?(File.expand_path('../legion-settings', __dir__))

gem 'legion-apollo', path: '../legion-apollo' if File.exist?(File.expand_path('../legion-apollo', __dir__))
gem 'lex-agentic-memory', path: '../extensions-agentic/lex-agentic-memory' if File.exist?(File.expand_path('../extensions-agentic/lex-agentic-memory', __dir__))
gem 'lex-llm-gateway', path: '../extensions-core/lex-llm-gateway' if File.exist?(File.expand_path('../extensions-core/lex-llm-gateway', __dir__))
gem 'lex-microsoft_teams', path: '../extensions/lex-microsoft_teams' if File.exist?(File.expand_path('../extensions/lex-microsoft_teams', __dir__))

gem 'pg'

gem 'kramdown', '>= 2.0'
gem 'mysql2'

group :test do
  gem 'graphql'
  gem 'lex-codegen'
  gem 'lex-eval'
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-legion'
  gem 'rubocop-rspec'
  gem 'ruby_llm'
  gem 'simplecov'
end
