# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/cli/init/environment_detector'
require 'legion/cli/init/config_generator'

RSpec.describe Legion::CLI::InitHelpers::EnvironmentDetector do
  describe '.detect' do
    it 'returns a hash with expected keys' do
      result = described_class.detect
      expect(result).to have_key(:rabbitmq)
      expect(result).to have_key(:database)
      expect(result).to have_key(:vault)
      expect(result).to have_key(:redis)
      expect(result).to have_key(:git)
      expect(result).to have_key(:existing_config)
    end

    it 'database always returns available' do
      result = described_class.detect
      expect(result[:database][:available]).to be true
    end

    it 'detects git repo when .git exists' do
      result = described_class.detect
      expect(result[:git][:available]).to eq(Dir.exist?('.git'))
    end

    it 'detects VAULT_ADDR from env' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('VAULT_ADDR').and_return('http://localhost:8200')
      result = described_class.detect
      expect(result[:vault][:available]).to be true
      expect(result[:vault][:source]).to eq('env')
    end

    it 'detects DATABASE_URL from env' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DATABASE_URL').and_return('postgres://localhost/test')
      result = described_class.detect
      expect(result[:database][:adapter]).to eq('postgresql')
    end

    it 'returns rabbitmq unavailable when socket fails' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('AMQP_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('RABBITMQ_URL').and_return(nil)
      allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      result = described_class.detect
      expect(result[:rabbitmq][:available]).to be false
    end
  end
end

RSpec.describe Legion::CLI::InitHelpers::ConfigGenerator do
  let(:tmpdir) { Dir.mktmpdir('init-test') }
  let(:config_dir) { File.join(tmpdir, 'settings') }

  before do
    stub_const('Legion::CLI::InitHelpers::ConfigGenerator::CONFIG_DIR', config_dir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe '.scaffold_workspace' do
    it 'creates .legion directory structure' do
      described_class.scaffold_workspace(tmpdir)
      expect(Dir).to exist(File.join(tmpdir, '.legion'))
      expect(Dir).to exist(File.join(tmpdir, '.legion', 'agents'))
      expect(Dir).to exist(File.join(tmpdir, '.legion', 'skills'))
      expect(Dir).to exist(File.join(tmpdir, '.legion', 'memory'))
    end

    it 'creates settings.json' do
      described_class.scaffold_workspace(tmpdir)
      expect(File).to exist(File.join(tmpdir, '.legion', 'settings.json'))
    end

    it 'does not overwrite existing settings.json' do
      FileUtils.mkdir_p(File.join(tmpdir, '.legion'))
      settings_path = File.join(tmpdir, '.legion', 'settings.json')
      File.write(settings_path, '{"existing": true}')

      described_class.scaffold_workspace(tmpdir)
      expect(File.read(settings_path)).to eq('{"existing": true}')
    end

    it 'adds gitignore entries' do
      described_class.scaffold_workspace(tmpdir)
      gitignore = File.read(File.join(tmpdir, '.gitignore'))
      expect(gitignore).to include('.legion-context/')
      expect(gitignore).to include('.legion-worktrees/')
    end

    it 'does not duplicate gitignore entries on second run' do
      described_class.scaffold_workspace(tmpdir)
      described_class.scaffold_workspace(tmpdir)
      gitignore = File.read(File.join(tmpdir, '.gitignore'))
      expect(gitignore.scan('.legion-context/').length).to eq(1)
    end

    it 'returns workspace directory path' do
      result = described_class.scaffold_workspace(tmpdir)
      expect(result).to eq(File.join(tmpdir, '.legion'))
    end
  end

  describe '.generate' do
    it 'creates config directory' do
      described_class.generate({})
      expect(Dir).to exist(config_dir)
    end

    it 'skips existing files without force flag' do
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, 'core.json'), '{"existing": true}')

      result = described_class.generate({})
      expect(result).to be_empty
    end
  end
end
