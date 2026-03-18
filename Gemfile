# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Local development: override gemspec deps with sibling repo paths.
# CI uses published gem versions from RubyGems via gemspec.
unless ENV['CI']
  gem 'legion-cache',     path: '../legion-cache'
  gem 'legion-crypt',     path: '../legion-crypt'
  gem 'legion-data',      path: '../legion-data'
  gem 'legion-gaia',      path: '../legion-gaia'
  gem 'legion-json',      path: '../legion-json'
  gem 'legion-llm',       path: '../legion-llm'
  gem 'legion-logging',   path: '../legion-logging'
  gem 'legion-rbac',      path: '../legion-rbac'
  gem 'legion-settings',  path: '../legion-settings'
  gem 'legion-transport', path: '../legion-transport'

  # Core extensions
  gem 'lex-codegen',     path: '../extensions-core/lex-codegen'
  gem 'lex-conditioner', path: '../extensions-core/lex-conditioner'
  gem 'lex-exec',        path: '../extensions-core/lex-exec'
  gem 'lex-health',      path: '../extensions-core/lex-health'
  gem 'lex-lex',         path: '../extensions-core/lex-lex'
  gem 'lex-log',         path: '../extensions-core/lex-log'
  gem 'lex-metering',    path: '../extensions-core/lex-metering'
  gem 'lex-node',        path: '../extensions-core/lex-node'
  gem 'lex-ping',        path: '../extensions-core/lex-ping'
  gem 'lex-scheduler',   path: '../extensions-core/lex-scheduler'
  gem 'lex-tasker',      path: '../extensions-core/lex-tasker'
  gem 'lex-task_pruner', path: '../extensions-core/task_pruner'
  gem 'lex-telemetry',   path: '../extensions-core/lex-telemetry'
  gem 'lex-transformer', path: '../extensions-core/lex-transformer'

  # Common service extensions
  gem 'lex-microsoft_teams', path: '../extensions/lex-microsoft_teams'
  gem 'lex-tfe',             path: '../extensions/lex-tfe'

  # Core framework
  gem 'legion-tty', path: '../legion-tty'

  # AI extensions
  gem 'lex-claude', path: '../extensions-ai/lex-claude'
  gem 'lex-gemini', path: '../extensions-ai/lex-gemini'
  gem 'lex-openai', path: '../extensions-ai/lex-openai'

  # Agentic extensions — domain gems (consolidated from 232 individual source gems)
  gem 'lex-agentic-affect',       path: '../extensions-agentic/lex-agentic-affect'
  gem 'lex-agentic-attention',    path: '../extensions-agentic/lex-agentic-attention'
  gem 'lex-agentic-defense',      path: '../extensions-agentic/lex-agentic-defense'
  gem 'lex-agentic-executive',    path: '../extensions-agentic/lex-agentic-executive'
  gem 'lex-agentic-homeostasis',  path: '../extensions-agentic/lex-agentic-homeostasis'
  gem 'lex-agentic-imagination',  path: '../extensions-agentic/lex-agentic-imagination'
  gem 'lex-agentic-inference',    path: '../extensions-agentic/lex-agentic-inference'
  gem 'lex-agentic-integration',  path: '../extensions-agentic/lex-agentic-integration'
  gem 'lex-agentic-language',     path: '../extensions-agentic/lex-agentic-language'
  gem 'lex-agentic-learning',     path: '../extensions-agentic/lex-agentic-learning'
  gem 'lex-agentic-memory',       path: '../extensions-agentic/lex-agentic-memory'
  gem 'lex-agentic-self',         path: '../extensions-agentic/lex-agentic-self'
  gem 'lex-agentic-social',       path: '../extensions-agentic/lex-agentic-social'
end

gem 'mysql2'

group :test do
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'ruby_llm'
  gem 'simplecov'
end
