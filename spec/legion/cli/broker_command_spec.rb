# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/broker_command'

RSpec.describe Legion::CLI::Broker do
  describe 'Thor registration' do
    it 'has a stats command' do
      expect(described_class.commands).to have_key('stats')
    end

    it 'has a cleanup command' do
      expect(described_class.commands).to have_key('cleanup')
    end
  end

  describe 'Main registration' do
    it 'registers broker on Legion::CLI::Main' do
      expect(Legion::CLI::Main.subcommand_classes).to have_key('broker')
    end
  end
end
