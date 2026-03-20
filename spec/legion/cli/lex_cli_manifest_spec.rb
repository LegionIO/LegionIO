# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/lex_cli_manifest'

RSpec.describe Legion::CLI::LexCliManifest do
  let(:cache_dir) { Dir.mktmpdir }
  let(:manifest) { described_class.new(cache_dir: cache_dir) }

  after { FileUtils.remove_entry(cache_dir) }

  describe '#write_manifest' do
    it 'writes a JSON file for a gem with CLI modules' do
      manifest.write_manifest(
        gem_name: 'lex-microsoft_teams',
        gem_version: '0.6.0',
        alias_name: 'teams',
        commands: {
          'auth' => {
            class_name: 'Legion::Extensions::MicrosoftTeams::CLI::Auth',
            methods: {
              'login' => { desc: 'Authenticate via browser', args: %w[tenant_id client_id] },
              'status' => { desc: 'Show auth state', args: [] }
            }
          }
        }
      )

      path = File.join(cache_dir, 'lex-microsoft_teams.json')
      expect(File.exist?(path)).to be true
      data = JSON.parse(File.read(path))
      expect(data['alias']).to eq('teams')
      expect(data['commands']['auth']['methods']['login']['desc']).to eq('Authenticate via browser')
    end
  end

  describe '#read_manifest' do
    it 'returns nil for missing gem' do
      expect(manifest.read_manifest('lex-nonexistent')).to be_nil
    end

    it 'returns parsed manifest for existing gem' do
      manifest.write_manifest(gem_name: 'lex-test', gem_version: '1.0', alias_name: nil, commands: {})
      result = manifest.read_manifest('lex-test')
      expect(result['gem']).to eq('lex-test')
    end
  end

  describe '#resolve_alias' do
    it 'returns gem name for a known alias' do
      manifest.write_manifest(gem_name: 'lex-microsoft_teams', gem_version: '0.6.0',
                              alias_name: 'teams', commands: {})
      expect(manifest.resolve_alias('teams')).to eq('lex-microsoft_teams')
    end

    it 'returns nil for unknown alias' do
      expect(manifest.resolve_alias('unknown')).to be_nil
    end
  end

  describe '#all_manifests' do
    it 'returns all cached manifests' do
      manifest.write_manifest(gem_name: 'lex-a', gem_version: '1.0', alias_name: nil, commands: {})
      manifest.write_manifest(gem_name: 'lex-b', gem_version: '1.0', alias_name: nil, commands: {})
      expect(manifest.all_manifests.length).to eq(2)
    end
  end

  describe '#stale?' do
    it 'returns true for missing manifest' do
      expect(manifest.stale?('lex-unknown', '1.0')).to be true
    end

    it 'returns false when version matches' do
      manifest.write_manifest(gem_name: 'lex-test', gem_version: '1.0', alias_name: nil, commands: {})
      expect(manifest.stale?('lex-test', '1.0')).to be false
    end

    it 'returns true when version differs' do
      manifest.write_manifest(gem_name: 'lex-test', gem_version: '1.0', alias_name: nil, commands: {})
      expect(manifest.stale?('lex-test', '2.0')).to be true
    end
  end
end
