# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Local development: override gemspec deps with sibling repo paths.
# CI uses published gem versions from RubyGems via gemspec.
unless ENV['CI']
  gem 'legion-cache',     path: '../legion-cache'
  gem 'legion-crypt',     path: '../legion-crypt'
  gem 'legion-data',      path: '../legion-data'
  gem 'legion-json',      path: '../legion-json'
  gem 'legion-llm',       path: '../legion-llm'
  gem 'legion-logging',   path: '../legion-logging'
  gem 'legion-settings',  path: '../legion-settings'
  gem 'legion-transport', path: '../legion-transport'

  gem 'lex-health', path: '../extensions-core/lex-health'
  gem 'lex-node',   path: '../extensions-core/lex-node'

  gem 'lex-coldstart',       path: '../extensions-agentic/lex-coldstart'
  gem 'lex-conflict',        path: '../extensions-agentic/lex-conflict'
  gem 'lex-consent',         path: '../extensions-agentic/lex-consent'
  gem 'lex-cortex',          path: '../extensions-agentic/lex-cortex'
  gem 'lex-dream',           path: '../extensions-agentic/lex-dream'
  gem 'lex-emotion',         path: '../extensions-agentic/lex-emotion'
  gem 'lex-extinction',      path: '../extensions-agentic/lex-extinction'
  gem 'lex-governance',      path: '../extensions-agentic/lex-governance'
  gem 'lex-identity',        path: '../extensions-agentic/lex-identity'
  gem 'lex-memory',          path: '../extensions-agentic/lex-memory'
  gem 'lex-mesh',            path: '../extensions-agentic/lex-mesh'
  gem 'lex-microsoft_teams', path: '../extensions/lex-microsoft_teams'
  gem 'lex-prediction',      path: '../extensions-agentic/lex-prediction'
  gem 'lex-privatecore',     path: '../extensions-agentic/lex-privatecore'
  gem 'lex-tick',            path: '../extensions-agentic/lex-tick'
  gem 'lex-trust',           path: '../extensions-agentic/lex-trust'
end

gem 'mysql2'

group :test do
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'simplecov'
end
