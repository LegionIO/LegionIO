# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/init/config_generator'
require 'tmpdir'

RSpec.describe Legion::CLI::InitHelpers::ConfigGenerator do
  describe '.scaffold_workspace' do
    it 'creates .legion directory structure' do
      Dir.mktmpdir do |dir|
        described_class.scaffold_workspace(dir)
        expect(Dir.exist?(File.join(dir, '.legion', 'agents'))).to be true
        expect(Dir.exist?(File.join(dir, '.legion', 'skills'))).to be true
        expect(Dir.exist?(File.join(dir, '.legion', 'memory'))).to be true
        expect(File.exist?(File.join(dir, '.legion', 'settings.json'))).to be true
      end
    end

    it 'does not overwrite existing settings.json' do
      Dir.mktmpdir do |dir|
        legion_dir = File.join(dir, '.legion')
        FileUtils.mkdir_p(legion_dir)
        File.write(File.join(legion_dir, 'settings.json'), '{"custom": true}')

        described_class.scaffold_workspace(dir)
        content = File.read(File.join(legion_dir, 'settings.json'))
        expect(content).to eq('{"custom": true}')
      end
    end
  end
end
