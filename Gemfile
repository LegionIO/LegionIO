# frozen_string_literal: true

source 'https://rubygems.org'

gemspec
gem 'pg'

gem 'kramdown', '>= 2.0'
gem 'mysql2'

companion_root = File.directory?(File.expand_path('.ci-dependencies', __dir__)) ? '.ci-dependencies' : '..'
%w[legion-data legion-settings legion-transport legion-mcp].each do |dependency|
  path = File.expand_path("#{companion_root}/#{dependency}", __dir__)
  gem dependency, path: path if File.directory?(path)
end
gem 'legion-logging', path: '../legion-logging' if File.directory?(File.expand_path('../legion-logging', __dir__))

gem 'legion-apollo', path: '../legion-apollo' if File.directory?(File.expand_path('../legion-apollo', __dir__))
gem 'legion-gaia', path: '../legion-gaia' if File.directory?(File.expand_path('../legion-gaia', __dir__))
gem 'legion-llm', path: '../legion-llm' if File.directory?(File.expand_path('../legion-llm', __dir__))
gem 'legion-tty', path: '../legion-tty' if File.directory?(File.expand_path('../legion-tty', __dir__))

gem 'lex-apollo', path: '../extensions/lex-apollo' if File.directory?(File.expand_path('../extensions/lex-apollo', __dir__))
gem 'lex-llm', path: '../extensions-ai/lex-llm' if File.directory?(File.expand_path('../extensions-ai/lex-llm', __dir__))
# gem 'lex-microsoft_teams', path: '../extensions/lex-microsoft_teams' if File.directory?(File.expand_path('../extensions/lex-microsoft_teams', __dir__))

gem 'lex-lex', path: '../extensions/lex-lex' if File.directory?(File.expand_path('../extensions/lex-lex', __dir__))
gem 'lex-llm-ledger', path: '../extensions-ai/lex-llm-ledger' if File.directory?(File.expand_path('../extensions-ai/lex-llm-ledger', __dir__))
gem 'lex-scheduler', path: '../extensions/lex-scheduler' if File.directory?(File.expand_path('../extensions/lex-scheduler', __dir__))
gem 'lex-tasker', path: '../extensions/lex-tasker' if File.directory?(File.expand_path('../extensions/lex-tasker', __dir__))

if File.directory?(File.expand_path('../extensions-identity/lex-identity-entra', __dir__))
  gem 'lex-identity-entra', path: '../extensions-identity/lex-identity-entra'
end
if File.directory?(File.expand_path('../extensions-identity/lex-identity-kerberos', __dir__))
  gem 'lex-identity-kerberos', path: '../extensions-identity/lex-identity-kerberos'
end

gem 'lex-kerberos', path: '../extensions-identity/lex-kerberos' if File.directory?(File.expand_path('../extensions-identity/lex-kerberos', __dir__))

if File.directory?(File.expand_path('../extensions-identity/lex-identity-system', __dir__))
  gem 'lex-identity-system', path: '../extensions-identity/lex-identity-system'
end

%w[anthropic azure-foundry bedrock gemini mlx ollama openai vertex vllm].each do |provider|
  provider_path = "../extensions-ai/lex-llm-#{provider}"
  gem "lex-llm-#{provider}", path: provider_path if File.directory?(File.expand_path(provider_path, __dir__))
end

group :test do
  gem 'faraday'
  gem 'faraday-net_http'
  gem 'graphql'
  rbac_path = File.expand_path("#{companion_root}/legion-rbac", __dir__)
  rbac_options = File.directory?(rbac_path) ? { path: rbac_path } : {}
  gem 'legion-rbac', '>= 0.3.5', **rbac_options
  gem 'lex-codegen'
  gem 'lex-eval'
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-legion'
  gem 'rubocop-rspec'
  gem 'simplecov'
  gem 'sqlite3'
end
