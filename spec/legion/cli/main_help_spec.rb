# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Main do
  describe 'start option metadata' do
    it 'does not hard-default log_level, so settings or explicit CLI values can win' do
      expect(described_class.commands['start'].options[:log_level].default).to be_nil
    end
  end

  describe '.start' do
    def capture_help(*args)
      out = StringIO.new
      err = StringIO.new
      original_stdout = $stdout
      original_stderr = $stderr
      $stdout = out
      $stderr = err
      described_class.start(args)
      [out.string, err.string]
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end

    it 'shows start help when invoked as help start' do
      stdout, stderr = capture_help('help', 'start')

      expect(stderr).to eq('')
      expect(stdout).to include('Usage:')
      expect(stdout).to match(/^\s*\S+\s+start$/)
      expect(stdout).to include('--log-level=LOG_LEVEL')
      expect(stdout).to include('--http-port=N')
    end

    it 'normalizes start --help to the same help output' do
      help_stdout, = capture_help('help', 'start')
      dash_help_stdout, dash_help_stderr = capture_help('start', '--help')

      expect(dash_help_stderr).to eq('')
      expect(dash_help_stdout).to eq(help_stdout)
    end
  end
end
