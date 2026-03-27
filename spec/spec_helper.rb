# frozen_string_literal: true

require 'rspec'
require 'simplecov'
SimpleCov.start
# Prevent SimpleCov from treating RSpec's SystemExit(0) as an error (Ruby 3.4 compat)
SimpleCov.define_singleton_method(:previous_error?) { |_| false }
require 'bundler/setup'
require 'legion'
require 'legion/service'
require 'legion/logging'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
