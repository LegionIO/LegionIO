# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'legion/cli/config_command'
require 'legion/cli/config_import'

RSpec.describe Legion::CLI::Config, '#reset' do
  let(:out) do
    instance_double(
      Legion::CLI::Output::Formatter,
      success: nil, warn: nil, error: nil,
      header: nil, spacer: nil, json: nil
    )
  end
  let(:cli) { described_class.new }
  let(:tmpdir) { Dir.mktmpdir('legion_config_reset') }

  before do
    allow(cli).to receive(:formatter).and_return(out)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe 'when files exist' do
    before do
      File.write(File.join(tmpdir, 'transport.json'), '{}')
      File.write(File.join(tmpdir, 'llm.json'), '{}')
      File.write(File.join(tmpdir, 'keep.yaml'), 'not json')
    end

    context 'with --force' do
      before do
        allow(cli).to receive(:options).and_return(json: false, no_color: true, force: true, config_dir: tmpdir)
      end

      it 'removes all .json files' do
        cli.reset
        expect(Dir.glob(File.join(tmpdir, '*.json'))).to be_empty
      end

      it 'preserves non-json files' do
        cli.reset
        expect(File.exist?(File.join(tmpdir, 'keep.yaml'))).to be true
      end

      it 'reports the count removed' do
        expect(out).to receive(:success).with(a_string_matching(/removed 2 json file/i))
        cli.reset
      end
    end

    context 'with --json and --force' do
      before do
        allow(cli).to receive(:options).and_return(json: true, no_color: true, force: true, config_dir: tmpdir)
      end

      it 'outputs json with removed files' do
        expect(out).to receive(:json).with(hash_including(:removed, :directory))
        cli.reset
      end
    end

    context 'without --force (interactive confirmation)' do
      before do
        allow(cli).to receive(:options).and_return(json: false, no_color: true, force: false, config_dir: tmpdir)
      end

      it 'removes files when user confirms with y' do
        allow($stdin).to receive(:gets).and_return("y\n")
        cli.reset
        expect(Dir.glob(File.join(tmpdir, '*.json'))).to be_empty
      end

      it 'removes files when user confirms with yes' do
        allow($stdin).to receive(:gets).and_return("yes\n")
        cli.reset
        expect(Dir.glob(File.join(tmpdir, '*.json'))).to be_empty
      end

      it 'aborts when user declines' do
        allow($stdin).to receive(:gets).and_return("n\n")
        cli.reset
        expect(Dir.glob(File.join(tmpdir, '*.json')).size).to eq(2)
      end

      it 'aborts on empty input' do
        allow($stdin).to receive(:gets).and_return("\n")
        cli.reset
        expect(Dir.glob(File.join(tmpdir, '*.json')).size).to eq(2)
      end

      it 'prints abort message when declined' do
        allow($stdin).to receive(:gets).and_return("n\n")
        expect(out).to receive(:warn).with('Aborted.')
        cli.reset
      end
    end
  end

  describe 'when no files exist' do
    before do
      FileUtils.mkdir_p(tmpdir)
      allow(cli).to receive(:options).and_return(json: false, no_color: true, force: true, config_dir: tmpdir)
    end

    it 'warns that no files were found' do
      expect(out).to receive(:warn).with(a_string_including('No JSON files found'))
      cli.reset
    end
  end

  describe 'uses SETTINGS_DIR by default' do
    before do
      allow(cli).to receive(:options).and_return(json: false, no_color: true, force: true, config_dir: nil)
      allow(Dir).to receive(:glob).and_return([])
    end

    it 'falls back to ConfigImport::SETTINGS_DIR' do
      expect(Dir).to receive(:glob).with(File.join(Legion::CLI::ConfigImport::SETTINGS_DIR, '*.json'))
      cli.reset
    end
  end
end
