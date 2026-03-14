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
end
