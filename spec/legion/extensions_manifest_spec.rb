# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/lex_cli_manifest'

RSpec.describe 'Legion::Extensions CLI manifest wiring' do
  let(:cache_dir) { Dir.mktmpdir }

  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  after { FileUtils.remove_entry(cache_dir) }

  describe '.build_manifest_commands' do
    let(:runner_module) { Module.new }
    let(:extension) do
      rm = runner_module
      mod = Module.new
      mod.define_singleton_method(:runners) do
        {
          search:       {
            runner_name:   :search,
            runner_module: rm,
            class_methods: {
              execute:        { args: [%i[keyreq query], %i[key limit]] },
              _internal_hook: { args: [] }
            }
          },
          empty_runner: {
            runner_name:   :empty_runner,
            runner_module: Module.new,
            class_methods: {}
          }
        }
      end
      mod
    end

    it 'builds commands from runners, skipping underscore-prefixed methods' do
      result = Legion::Extensions.send(:build_manifest_commands, extension)
      expect(result).to have_key('search')
      expect(result['search'][:methods]).to have_key('execute')
      expect(result['search'][:methods]).not_to have_key('_internal_hook')
    end

    it 'skips runners with no public methods' do
      result = Legion::Extensions.send(:build_manifest_commands, extension)
      expect(result).not_to have_key('empty_runner')
    end

    it 'includes argument metadata' do
      result = Legion::Extensions.send(:build_manifest_commands, extension)
      args = result['search'][:methods]['execute'][:args]
      expect(args).to include('query:keyreq')
      expect(args).to include('limit:key')
    end

    it 'returns empty hash when extension has no runners method' do
      bare = Module.new
      expect(Legion::Extensions.send(:build_manifest_commands, bare)).to eq({})
    end
  end

  describe '.write_lex_cli_manifest' do
    let(:extension) do
      mod = Module.new
      mod.const_set(:VERSION, '1.2.3')
      mod.define_singleton_method(:runners) { {} }
      mod
    end
    let(:entry) { { gem_name: 'lex-test-manifest' } }

    it 'writes manifest when stale' do
      manifest = Legion::CLI::LexCliManifest.new(cache_dir: cache_dir)
      allow(Legion::CLI::LexCliManifest).to receive(:new).and_return(manifest)

      Legion::Extensions.send(:write_lex_cli_manifest, entry, extension)

      data = manifest.read_manifest('lex-test-manifest')
      expect(data).not_to be_nil
      expect(data['version']).to eq('1.2.3')
      expect(data['alias']).to eq('test-manifest')
    end

    it 'skips write when manifest is fresh' do
      manifest = Legion::CLI::LexCliManifest.new(cache_dir: cache_dir)
      manifest.write_manifest(gem_name: 'lex-test-manifest', gem_version: '1.2.3',
                              alias_name: 'test-manifest', commands: {})
      allow(Legion::CLI::LexCliManifest).to receive(:new).and_return(manifest)
      allow(manifest).to receive(:write_manifest).and_call_original

      Legion::Extensions.send(:write_lex_cli_manifest, entry, extension)

      expect(manifest).not_to have_received(:write_manifest)
    end

    it 'does not raise on error' do
      allow(Legion::CLI::LexCliManifest).to receive(:new).and_raise(Errno::EACCES, 'permission denied')
      expect { Legion::Extensions.send(:write_lex_cli_manifest, entry, extension) }.not_to raise_error
    end
  end
end
