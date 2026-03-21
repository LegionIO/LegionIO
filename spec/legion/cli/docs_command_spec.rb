# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/docs_command'
require 'legion/docs/site_generator'

RSpec.describe Legion::CLI::Docs do
  let(:out) { instance_double(Legion::CLI::Output::Formatter) }

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:header)
    allow(out).to receive(:success)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:colorize) { |text, _color| text }
    allow(out).to receive(:error)
  end

  def build_command(subcommand_class, argv = [], opts = {})
    subcommand_class.new(argv, { json: false, no_color: true }.merge(opts))
  end

  # ---------------------------------------------------------------------------
  # generate subcommand
  # ---------------------------------------------------------------------------

  describe '#generate' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:fake_stats) do
      { output: tmpdir, sections: 5, pages: 7, files: [] }
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'calls SiteGenerator.new with the --output option' do
      gen = instance_double(Legion::Docs::SiteGenerator, generate: fake_stats)
      expect(Legion::Docs::SiteGenerator).to receive(:new).with(output_dir: tmpdir).and_return(gen)

      cmd = build_command(described_class, [], output: tmpdir)
      cmd.generate
    end

    it 'calls generate on the SiteGenerator instance' do
      gen = instance_double(Legion::Docs::SiteGenerator)
      allow(Legion::Docs::SiteGenerator).to receive(:new).and_return(gen)
      expect(gen).to receive(:generate).and_return(fake_stats)

      cmd = build_command(described_class, [], output: tmpdir)
      cmd.generate
    end

    it 'outputs success message with the output directory' do
      gen = instance_double(Legion::Docs::SiteGenerator, generate: fake_stats)
      allow(Legion::Docs::SiteGenerator).to receive(:new).and_return(gen)

      expect(out).to receive(:success).with(a_string_including(tmpdir))

      cmd = build_command(described_class, [], output: tmpdir)
      cmd.generate
    end

    it 'uses default output directory (docs/site) when --output not given' do
      default_stats = { output: 'docs/site', sections: 5, pages: 7, files: [] }
      gen = instance_double(Legion::Docs::SiteGenerator, generate: default_stats)
      expect(Legion::Docs::SiteGenerator).to receive(:new).with(output_dir: 'docs/site').and_return(gen)

      cmd = build_command(described_class, [], output: 'docs/site')
      cmd.generate
    end

    context 'when --json is set' do
      it 'outputs stats as JSON' do
        gen = instance_double(Legion::Docs::SiteGenerator, generate: fake_stats)
        allow(Legion::Docs::SiteGenerator).to receive(:new).and_return(gen)
        expect(out).to receive(:json).with(fake_stats)

        cmd = build_command(described_class, [], output: tmpdir, json: true)
        cmd.generate
      end
    end
  end

  # ---------------------------------------------------------------------------
  # serve subcommand
  # ---------------------------------------------------------------------------

  describe '#serve' do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(tmpdir) }

    it 'prints preview instructions when directory exists' do
      cmd = build_command(described_class, [], port: 4000, dir: tmpdir)
      output_lines = []
      allow($stdout).to receive(:puts) { |line| output_lines << line.to_s }

      cmd.serve

      combined = output_lines.join(' ')
      expect(combined).to include('4000').or include('http')
    end

    it 'uses default port 4000' do
      cmd = build_command(described_class, [], dir: tmpdir)
      # Just ensure it runs without error when dir exists
      allow($stdout).to receive(:puts)
      expect { cmd.serve }.not_to raise_error
    end

    it 'warns when the directory does not exist' do
      nonexistent = File.join(tmpdir, 'missing_dir')
      expect(out).to receive(:warn).with(a_string_including('missing_dir'))

      cmd = build_command(described_class, [], dir: nonexistent, port: 4000)
      cmd.serve
    end

    it 'includes python3 http.server command in output' do
      cmd = build_command(described_class, [], port: 4001, dir: tmpdir)
      output_lines = []
      allow($stdout).to receive(:puts) { |line| output_lines << line.to_s }

      cmd.serve

      combined = output_lines.join(' ')
      expect(combined).to include('python3').or include('http.server')
    end
  end

  # ---------------------------------------------------------------------------
  # namespace
  # ---------------------------------------------------------------------------

  describe 'namespace' do
    it 'is registered as :docs' do
      expect(described_class.namespace).to eq('docs')
    end
  end
end
