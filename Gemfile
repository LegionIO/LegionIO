# frozen_string_literal: true

source 'https://rubygems.org'

gemspec
gem 'pg'

gem 'kramdown', '>= 2.0'
gem 'mysql2'

group :test do
  gem 'legion-data', path: '../legion-data' if File.exist?(File.expand_path('../legion-data', __dir__))
  gem 'legion-logging', path: '../legion-logging' if File.exist?(File.expand_path('../legion-logging', __dir__))
  gem 'legion-settings', path: '../legion-settings' if File.exist?(File.expand_path('../legion-settings', __dir__))

  gem 'legion-apollo', path: '../legion-apollo' if File.exist?(File.expand_path('../legion-apollo', __dir__))
  gem 'legion-gaia', path: '../legion-gaia' if File.exist?(File.expand_path('../legion-gaia', __dir__))
  gem 'legion-llm', path: '../legion-llm' if File.exist?(File.expand_path('../legion-llm', __dir__))
  gem 'legion-mcp', path: '../legion-mcp' if File.exist?(File.expand_path('../legion-mcp', __dir__))
  gem 'legion-tty', path: '../legion-tty' if File.exist?(File.expand_path('../legion-tty', __dir__))

  gem 'lex-apollo', path: '../extensions/lex-apollo' if File.exist?(File.expand_path('../extensions/lex-apollo', __dir__))
  gem 'lex-llm', path: '../extensions-ai/lex-llm' if File.exist?(File.expand_path('../extensions-ai/lex-llm', __dir__))
  gem 'lex-llm-ledger', path: '../extensions-ai/lex-llm-ledger' if File.exist?(File.expand_path('../extensions-ai/lex-llm-ledger', __dir__))

  if File.exist?(File.expand_path('../extensions-identity/lex-identity-entra', __dir__))
    gem 'lex-identity-entra', path: '../extensions-identity/lex-identity-entra'
  end
  if File.exist?(File.expand_path('../extensions-identity/lex-identity-kerberos', __dir__))
    gem 'lex-identity-kerberos', path: '../extensions-identity/lex-identity-kerberos'
  end
  if File.exist?(File.expand_path('../extensions-identity/lex-identity-system', __dir__))
    gem 'lex-identity-system', path: '../extensions-identity/lex-identity-system'
  end

  %w[anthropic azure-foundry bedrock gemini mlx ollama openai vertex vllm].each do |provider|
    provider_path = "../extensions-ai/lex-llm-#{provider}"
    gem "lex-llm-#{provider}", path: provider_path if File.exist?(File.expand_path(provider_path, __dir__))
  end

  gem 'faraday'
  gem 'faraday-net_http'
  gem 'graphql'
  gem 'lex-codegen'
  gem 'lex-eval'
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-legion'
  gem 'rubocop-rspec'
  gem 'simplecov'
end
