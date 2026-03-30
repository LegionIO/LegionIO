# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/workflow_command'

RSpec.describe Legion::CLI::Workflow do
  it 'is a Thor subcommand' do
    expect(described_class.superclass).to eq(Thor)
  end

  it 'defines install command' do
    expect(described_class.all_commands).to have_key('install')
  end

  it 'defines list command' do
    expect(described_class.all_commands).to have_key('list')
  end

  it 'defines uninstall command' do
    expect(described_class.all_commands).to have_key('uninstall')
  end

  it 'defines status command' do
    expect(described_class.all_commands).to have_key('status')
  end

  it 'defaults to list' do
    expect(described_class.default_command).to eq('list')
  end
end
