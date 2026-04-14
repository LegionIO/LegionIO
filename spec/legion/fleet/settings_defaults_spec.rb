# frozen_string_literal: true

require 'spec_helper'
require 'legion/fleet/settings_defaults'

RSpec.describe Legion::Fleet::SettingsDefaults do
  describe '.defaults' do
    subject(:defaults) { described_class.defaults }

    it 'returns a hash' do
      expect(defaults).to be_a(Hash)
    end

    it 'includes fleet key' do
      expect(defaults).to have_key(:fleet)
    end

    it 'enables fleet by default' do
      expect(defaults[:fleet][:enabled]).to be true
    end

    it 'starts with empty sources list' do
      expect(defaults[:fleet][:sources]).to eq([])
    end

    it 'enables LLM escalation' do
      expect(defaults.dig(:fleet, :llm, :routing, :escalation, :enabled)).to be true
    end

    it 'sets default implementation max_iterations to 5' do
      expect(defaults.dig(:fleet, :implementation, :max_iterations)).to eq(5)
    end

    it 'sets default implementation validators to 3' do
      expect(defaults.dig(:fleet, :implementation, :validators)).to eq(3)
    end

    it 'uses worktree isolation by default' do
      expect(defaults.dig(:fleet, :workspace, :isolation)).to eq(:worktree)
    end

    it 'sets consent domain to fleet.shipping' do
      expect(defaults.dig(:fleet, :escalation, :consent_domain)).to eq('fleet.shipping')
    end
  end

  describe '.write_settings_file' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:settings_path) { File.join(tmpdir, 'fleet.json') }

    after { FileUtils.rm_rf(tmpdir) }

    it 'writes a valid JSON file' do
      described_class.write_settings_file(settings_path)
      expect(File.exist?(settings_path)).to be true
      data = JSON.parse(File.read(settings_path), symbolize_names: true)
      expect(data).to have_key(:fleet)
    end

    it 'does not overwrite existing file without force' do
      File.write(settings_path, '{"existing": true}')
      described_class.write_settings_file(settings_path, force: false)
      data = JSON.parse(File.read(settings_path))
      expect(data).to have_key('existing')
    end

    it 'overwrites existing file with force' do
      File.write(settings_path, '{"existing": true}')
      described_class.write_settings_file(settings_path, force: true)
      data = JSON.parse(File.read(settings_path), symbolize_names: true)
      expect(data).to have_key(:fleet)
    end
  end
end
