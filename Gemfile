# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'legion-data', path: '../legion-data' if File.exist?(File.expand_path('../legion-data', __dir__))
gem 'legion-gaia', path: '../legion-gaia' if File.exist?(File.expand_path('../legion-gaia', __dir__))
legion_llm_path = ENV.fetch('LEGION_LLM_PATH', '../legion-llm')
gem 'legion-llm', path: legion_llm_path if File.exist?(File.expand_path(legion_llm_path, __dir__))
gem 'legion-logging', path: '../legion-logging' if File.exist?(File.expand_path('../legion-logging', __dir__))
gem 'legion-mcp', path: '../legion-mcp' if File.exist?(File.expand_path('../legion-mcp', __dir__))
gem 'legion-settings', path: '../legion-settings' if File.exist?(File.expand_path('../legion-settings', __dir__))

gem 'legion-apollo', path: '../legion-apollo' if File.exist?(File.expand_path('../legion-apollo', __dir__))
gem 'lex-agentic-memory', path: '../extensions-agentic/lex-agentic-memory' if File.exist?(File.expand_path('../extensions-agentic/lex-agentic-memory', __dir__))
gem 'lex-llm', path: '../extensions-ai/lex-llm' if File.exist?(File.expand_path('../extensions-ai/lex-llm', __dir__))
gem 'lex-llm-ledger', path: '../extensions-ai/lex-llm-ledger' if File.exist?(File.expand_path('../extensions-ai/lex-llm-ledger', __dir__))
%w[anthropic azure-foundry bedrock gemini mlx ollama openai vertex vllm].each do |provider|
  provider_path = "../extensions-ai/lex-llm-#{provider}"
  gem "lex-llm-#{provider}", path: provider_path if File.exist?(File.expand_path(provider_path, __dir__))
end
gem 'lex-llm-gateway', path: '../extensions/lex-llm-gateway' if File.exist?(File.expand_path('../extensions/lex-llm-gateway', __dir__))
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
