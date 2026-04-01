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

  describe 'sandbox routing' do
    it 'defaults to direct execution when sandboxed_commands not enabled' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :sandboxed_commands, :enabled).and_return(nil)
      result = tool.execute(command: 'echo sandbox-test')
      expect(result).to include('sandbox-test')
      expect(result).to include('exit code: 0')
    end

    it 'uses sandbox when enabled and available' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :sandboxed_commands, :enabled).and_return(true)

      stub_const('Legion::Extensions::Exec::Runners::Shell', Module.new do
        def self.execute(command:, **)
          { success: true, stdout: "sandboxed: #{command}", stderr: '', exit_code: 0 }
        end
      end)

      result = tool.execute(command: 'echo hello')
      expect(result).to include('sandboxed: echo hello')
    end

    it 'returns blocked message when sandbox rejects command' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :sandboxed_commands, :enabled).and_return(true)

      stub_const('Legion::Extensions::Exec::Runners::Shell', Module.new do
        def self.execute(**)
          { success: false, error: :blocked, reason: 'rm not in allowlist' }
        end
      end)

      result = tool.execute(command: 'rm -rf /')
      expect(result).to include('blocked by sandbox')
      expect(result).to include('rm not in allowlist')
    end

    it 'falls back to direct execution when sandbox not loaded' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :sandboxed_commands, :enabled).and_return(true)
      hide_const('Legion::Extensions::Exec::Runners::Shell') if defined?(Legion::Extensions::Exec::Runners::Shell)

      result = tool.execute(command: 'echo fallback')
      expect(result).to include('fallback')
      expect(result).to include('exit code: 0')
    end
  end
end
