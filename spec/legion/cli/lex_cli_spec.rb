# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/lex_cli_manifest'

RSpec.describe 'LEX CLI dispatch' do
  let(:cache_dir) { Dir.mktmpdir }
  let(:manifest) { Legion::CLI::LexCliManifest.new(cache_dir: cache_dir) }

  after { FileUtils.remove_entry(cache_dir) }

  before do
    manifest.write_manifest(
      gem_name:    'lex-microsoft_teams',
      gem_version: '0.6.0',
      alias_name:  'teams',
      commands:    {
        'auth' => {
          class_name: 'Legion::Extensions::MicrosoftTeams::CLI::Auth',
          methods:    {
            'login'  => { desc: 'Authenticate via browser', args: %w[tenant_id client_id] },
            'status' => { desc: 'Show auth state', args: [] }
          }
        }
      }
    )
  end

  it 'resolves alias to gem name' do
    expect(manifest.resolve_alias('teams')).to eq('lex-microsoft_teams')
  end

  it 'finds commands in manifest' do
    gem_manifest = manifest.read_manifest('lex-microsoft_teams')
    expect(gem_manifest.dig('commands', 'auth', 'methods', 'login', 'desc')).to eq('Authenticate via browser')
  end

  it 'returns nil for unknown aliases' do
    expect(manifest.resolve_alias('nonexistent')).to be_nil
  end
end
