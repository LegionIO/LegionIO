# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/mode_command'

RSpec.describe Legion::CLI::Mode do
  let(:tmpdir) { Dir.mktmpdir }
  let(:role_file) { File.join(tmpdir, 'role.json') }

  before do
    stub_const('Legion::CLI::Mode::SETTINGS_DIR', tmpdir)
    stub_const('Legion::CLI::Mode::ROLE_FILE', role_file)
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe 'VALID_PROFILES' do
    it 'includes the five documented profiles' do
      expect(described_class::VALID_PROFILES).to contain_exactly(:core, :cognitive, :service, :dev, :custom)
    end
  end

  describe '#show' do
    it 'displays current process role and profile' do
      mode = described_class.new([], { json: true })
      expect { mode.show }.to output(/process_role/).to_stdout
    end
  end

  describe '#list' do
    it 'displays available profiles and roles' do
      mode = described_class.new([], { json: true })
      expect { mode.list }.to output(/profiles/).to_stdout
    end
  end

  describe '#set' do
    it 'writes profile to role.json' do
      mode = described_class.new([], { json: false, no_color: true })
      mode.set('dev')
      expect(File.exist?(role_file)).to be true
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:role, :profile)).to eq('dev')
    end

    it 'writes custom profile with extensions' do
      mode = described_class.new([], { json: false, no_color: true, extensions: 'tick,react,knowledge' })
      mode.set('custom')
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:role, :profile)).to eq('custom')
      expect(data.dig(:role, :extensions)).to eq(%w[tick react knowledge])
    end

    it 'writes process role when provided' do
      mode = described_class.new([], { json: false, no_color: true, process_role: 'worker' })
      mode.set
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:process, :role)).to eq('worker')
    end

    it 'rejects unknown profile names' do
      mode = described_class.new([], { json: false, no_color: true })
      expect { mode.set('bogus') }.to raise_error(SystemExit)
    end

    it 'rejects custom profile without --extensions' do
      mode = described_class.new([], { json: false, no_color: true })
      expect { mode.set('custom') }.to raise_error(SystemExit)
    end

    it 'rejects unknown process role' do
      mode = described_class.new([], { json: false, no_color: true, process_role: 'bogus' })
      expect { mode.set }.to raise_error(SystemExit)
    end

    it 'does not write config in dry-run mode' do
      mode = described_class.new([], { json: false, no_color: true, dry_run: true })
      mode.set('dev')
      expect(File.exist?(role_file)).to be false
    end

    it 'preserves existing config keys on update' do
      FileUtils.mkdir_p(tmpdir)
      File.write(role_file, JSON.pretty_generate({ role: { profile: 'core' }, custom_key: true }))

      mode = described_class.new([], { json: false, no_color: true })
      mode.set('dev')
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:role, :profile)).to eq('dev')
      expect(data[:custom_key]).to be true
    end

    it 'sets both profile and process role in a single call' do
      mode = described_class.new([], { json: false, no_color: true, process_role: 'worker' })
      mode.set('cognitive')
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:role, :profile)).to eq('cognitive')
      expect(data.dig(:process, :role)).to eq('worker')
    end

    it 'removes extensions key when switching away from custom' do
      FileUtils.mkdir_p(tmpdir)
      File.write(role_file, JSON.pretty_generate({ role: { profile: 'custom', extensions: %w[a b] } }))

      mode = described_class.new([], { json: false, no_color: true })
      mode.set('dev')
      data = JSON.parse(File.read(role_file), symbolize_names: true)
      expect(data.dig(:role, :profile)).to eq('dev')
      expect(data.dig(:role, :extensions)).to be_nil
    end
  end

  describe '#trigger_reload' do
    it 'does not raise when daemon is not running' do
      mode = described_class.new([], { json: false, no_color: true })
      out = Legion::CLI::Output::Formatter.new(json: false, color: false)
      expect { mode.send(:trigger_reload, out) }.not_to raise_error
    end
  end
end
