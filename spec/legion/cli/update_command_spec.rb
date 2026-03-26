# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/update_command'
require 'legion/cli/output'

RSpec.describe Legion::CLI::Update do
  let(:formatter) { Legion::CLI::Output::Formatter.new(json: false, color: false) }
  let(:instance) { described_class.new([], options) }
  let(:options) { { json: false, no_color: true, dry_run: false } }

  before do
    allow(instance).to receive(:formatter).and_return(formatter)
    allow(instance).to receive(:fetch_outdated).and_return({})
  end

  describe '#discover_legion_gems' do
    it 'always includes legionio' do
      gems = instance.send(:discover_legion_gems)
      expect(gems).to include('legionio')
    end

    it 'includes legion-* gems' do
      gems = instance.send(:discover_legion_gems)
      legion_gems = gems.select { |g| g.start_with?('legion-') }
      expect(legion_gems).not_to be_empty
    end

    it 'returns sorted unique list' do
      gems = instance.send(:discover_legion_gems)
      expect(gems).to eq(gems.uniq.sort)
    end
  end

  describe '#snapshot_versions' do
    it 'returns version hash for installed gems' do
      versions = instance.send(:snapshot_versions, ['legionio'])
      expect(versions['legionio']).to match(/\d+\.\d+\.\d+/)
    end

    it 'returns nil for missing gems' do
      versions = instance.send(:snapshot_versions, ['nonexistent-gem-xyz'])
      expect(versions['nonexistent-gem-xyz']).to be_nil
    end
  end

  describe '#parse_outdated' do
    it 'parses gem outdated output format' do
      outdated_output = "lex-kerberos (0.1.6 < 0.1.7)\nlegionio (1.5.0 < 1.6.0)\nrake (13.0.0 < 13.1.0)\n"
      allowed = %w[legionio lex-kerberos]
      result = instance.send(:parse_outdated, outdated_output, allowed)

      expect(result).to eq({
                             'lex-kerberos' => { local: '0.1.6', remote: '0.1.7' },
                             'legionio'     => { local: '1.5.0', remote: '1.6.0' }
                           })
    end

    it 'filters to only allowed gem names' do
      outdated_output = "rake (13.0.0 < 13.1.0)\nlex-kerberos (0.1.6 < 0.1.7)\n"
      result = instance.send(:parse_outdated, outdated_output, %w[lex-kerberos])

      expect(result.keys).to eq(['lex-kerberos'])
    end

    it 'returns empty hash for empty output' do
      result = instance.send(:parse_outdated, '', %w[legionio])
      expect(result).to eq({})
    end
  end

  describe '#gems (dry_run)' do
    let(:options) { { json: false, no_color: true, dry_run: true } }

    before do
      allow(instance).to receive(:discover_legion_gems).and_return(%w[legionio legion-json])
      allow(instance).to receive(:fetch_outdated).and_return(
        'legionio' => { local: '1.5.0', remote: '2.0.0' }
      )
    end

    it 'does not shell out to gem install' do
      output = StringIO.new
      $stdout = output
      expect(instance).not_to receive(:`).with(/gem install/)
      instance.gems
    ensure
      $stdout = STDOUT
    end

    it 'reports available updates' do
      output = StringIO.new
      $stdout = output
      instance.gems
      $stdout = STDOUT
      expect(output.string).to include('legionio')
    end
  end

  describe '#gems (json + dry_run)' do
    let(:options) { { json: true, no_color: true, dry_run: true } }

    before do
      allow(instance).to receive(:discover_legion_gems).and_return(%w[legionio])
      allow(instance).to receive(:fetch_outdated).and_return(
        'legionio' => { local: '1.5.0', remote: '2.0.0' }
      )
    end

    it 'outputs valid JSON with gems key' do
      output = StringIO.new
      $stdout = output
      instance.gems
      $stdout = STDOUT
      parsed = JSON.parse(output.string)
      expect(parsed).to have_key('gems')
      expect(parsed['dry_run']).to be true
    end
  end

  describe '#display_results' do
    it 'shows up-to-date message when nothing changed' do
      output = StringIO.new
      $stdout = output
      results = [{ name: 'legionio', status: 'current', from: '1.0.0' }]
      instance.send(:display_results, formatter, results, {}, {})
      $stdout = STDOUT
      expect(output.string).to include('already latest')
    end

    it 'shows updated message when version changed' do
      output = StringIO.new
      $stdout = output
      results = [{ name: 'legionio', status: 'installed' }]
      before_v = { 'legionio' => '1.0.0' }
      after_v = { 'legionio' => '1.1.0' }
      instance.send(:display_results, formatter, results, before_v, after_v)
      $stdout = STDOUT
      expect(output.string).to include('1.0.0')
      expect(output.string).to include('1.1.0')
    end

    it 'shows failure message on error' do
      output = StringIO.new
      $stdout = output
      results = [{ name: 'legionio', status: 'failed' }]
      instance.send(:display_results, formatter, results, {}, {})
      $stdout = STDOUT
      expect(output.string).to include('failed')
    end

    it 'shows available status for dry run results' do
      output = StringIO.new
      $stdout = output
      results = [{ name: 'legionio', status: 'available', from: '1.0.0', to: '2.0.0' }]
      instance.send(:display_results, formatter, results, {}, {})
      $stdout = STDOUT
      expect(output.string).to include('1.0.0')
      expect(output.string).to include('2.0.0')
    end

    it 'shows current status for dry run with no update' do
      output = StringIO.new
      $stdout = output
      results = [{ name: 'legionio', status: 'current', from: '1.0.0' }]
      instance.send(:display_results, formatter, results, {}, {})
      $stdout = STDOUT
      expect(output.string).to include('already latest')
    end
  end
end
