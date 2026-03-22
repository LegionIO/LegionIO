# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'legion-logging', path: '../legion-logging' if File.exist?(File.expand_path('../legion-logging', __dir__))

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
