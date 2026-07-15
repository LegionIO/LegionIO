# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Chat do
  it 'is defined as a Thor subcommand' do
    expect(Legion::CLI::Chat).to be < Thor
  end

  it 'has an interactive command' do
    expect(Legion::CLI::Chat.instance_methods).to include(:interactive)
  end

  it 'has a prompt command for headless mode' do
    expect(Legion::CLI::Chat.instance_methods).to include(:prompt)
  end

  describe 'daemon_client require path' do
    it 'resolves legion/llm/call/daemon_client without LoadError' do
      expect { require 'legion/llm/call/daemon_client' }.not_to raise_error
    end
  end
end
