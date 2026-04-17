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

require 'thor'
RSpec::Mocks::AnyInstance::Recorder.prepend(Module.new do
  private

  %i[observe! mark_invoked! restore_original_method! remove_dummy_method!].each do |meth|
    define_method(meth) do |method_name|
      return super(method_name) unless @klass < Thor

      @klass.no_commands_context.enter { super(method_name) }
    end
  end
end)
