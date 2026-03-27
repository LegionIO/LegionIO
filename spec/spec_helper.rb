# frozen_string_literal: true

require 'rspec'
require 'simplecov'
SimpleCov.start
# SimpleCov's at_exit interprets any $! (including RSpec's SystemExit(0) and
# thread IOErrors from Open3) as a "previous error" and forces exit(1).
# Override to let RSpec control the exit code.
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
