# frozen_string_literal: true

require 'spec_helper'

begin
  require 'ruby_llm'
  require 'legion/cli/chat/tools/run_command'
rescue LoadError
  # ruby_llm not available
end

RSpec.describe(defined?(RubyLLM) ? Legion::CLI::Chat::Tools::RunCommand : 'RunCommand (skipped)',
               skip: !defined?(RubyLLM) && 'requires ruby_llm') do
  let(:tool) { described_class.new }

  it 'executes a shell command and returns output' do
    result = tool.execute(command: 'echo hello')
    expect(result).to include('hello')
  end

  it 'returns exit code' do
    result = tool.execute(command: 'echo hello')
    expect(result).to include('exit code: 0')
  end

  it 'returns stderr on failure' do
    result = tool.execute(command: 'ls /nonexistent_path_12345')
    expect(result).to include('exit code')
  end

  it 'respects timeout' do
    result = tool.execute(command: 'sleep 10', timeout: 1)
    expect(result).to include('timed out')
  end
end
