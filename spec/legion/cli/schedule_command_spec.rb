# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/schedule_command'

RSpec.describe Legion::CLI::Schedule do
  let(:output) { StringIO.new }

  describe 'class' do
    it 'is a Thor subcommand' do
      expect(described_class).to be < Thor
    end

    it 'has list as default task' do
      expect(described_class.default_command).to eq('list')
    end

    it 'responds to list, show, add, remove, logs' do
      commands = described_class.commands.keys
      expect(commands).to include('list', 'show', 'add', 'remove', 'logs')
    end
  end
end
