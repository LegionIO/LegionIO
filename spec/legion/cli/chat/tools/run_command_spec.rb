# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/run_command'

RSpec.describe Legion::CLI::Chat::Tools::RunCommand do
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
