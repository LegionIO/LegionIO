# frozen_string_literal: true

require 'spec_helper'
require 'legion/registry'
require 'legion/registry/security_scanner'
require 'legion/cli/marketplace_command'
require 'legion/cli/output'

RSpec.describe Legion::CLI::Marketplace do
  let(:entry_attrs) do
    {
      name:        'lex-test',
      version:     '1.0.0',
      author:      'test-author',
      description: 'A test extension',
      risk_tier:   'low',
      airb_status: 'pending',
      status:      :active
    }
  end

  let(:out) { instance_double(Legion::CLI::Output::Formatter) }

  before(:each) do
    Legion::Registry.clear!
    Legion::Registry.register(Legion::Registry::Entry.new(**entry_attrs))

    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:json)
    allow(out).to receive(:spacer)
    allow(out).to receive(:detail)
    allow(out).to receive(:table)
    allow(out).to receive(:header)
    allow(out).to receive(:colorize).and_return('colored')
  end

  def build_command(opts = {})
    described_class.new([], { json: false, no_color: true }.merge(opts))
  end

  # ──────────────────────────────────────────────────────────
  # search
  # ──────────────────────────────────────────────────────────

  describe '#search' do
    it 'calls table with results when found' do
      expect(out).to receive(:table).with(%w[Name Version Status Description], anything)
      build_command.search('test')
    end

    it 'warns when no results found' do
      expect(out).to receive(:warn).with(/no extensions/i)
      build_command.search('zzzmissing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(array_including(hash_including(name: 'lex-test')))
      cmd.search('test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # info
  # ──────────────────────────────────────────────────────────

  describe '#info' do
    it 'shows detail for known extension' do
      expect(out).to receive(:header).with(/lex-test/)
      expect(out).to receive(:detail)
      build_command.info('lex-test')
    end

    it 'errors when extension not found' do
      expect(out).to receive(:error).with(/not found/)
      build_command.info('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(hash_including(name: 'lex-test'))
      cmd.info('lex-test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # list
  # ──────────────────────────────────────────────────────────

  describe '#list' do
    it 'calls table when extensions exist' do
      expect(out).to receive(:table).with(%w[Name Version Status Tier], anything)
      build_command.list
    end

    it 'warns when registry is empty' do
      Legion::Registry.clear!
      expect(out).to receive(:warn).with(/no extensions/i)
      build_command.list
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(array_including(hash_including(name: 'lex-test')))
      cmd.list
    end

    it 'filters by status option' do
      Legion::Registry.submit_for_review('lex-test')
      cmd = build_command(status: 'pending_review')
      expect(out).to receive(:table).with(anything, array_including(array_including('lex-test')))
      cmd.list
    end
  end

  # ──────────────────────────────────────────────────────────
  # submit
  # ──────────────────────────────────────────────────────────

  describe '#submit' do
    it 'succeeds for known extension' do
      expect(out).to receive(:success).with(/submitted/i)
      build_command.submit('lex-test')
    end

    it 'sets extension status to pending_review' do
      build_command.submit('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:pending_review)
    end

    it 'errors for unknown extension' do
      expect(out).to receive(:error).with(/not found/)
      build_command.submit('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(hash_including(status: 'pending_review'))
      cmd.submit('lex-test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # review
  # ──────────────────────────────────────────────────────────

  describe '#review' do
    it 'warns when no pending reviews' do
      expect(out).to receive(:warn).with(/no extensions pending/i)
      build_command.review
    end

    it 'shows table when pending reviews exist' do
      Legion::Registry.submit_for_review('lex-test')
      expect(out).to receive(:table).with(%w[Name Version Author Submitted], anything)
      build_command.review
    end

    it 'outputs json for pending reviews' do
      Legion::Registry.submit_for_review('lex-test')
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(array_including(hash_including(name: 'lex-test')))
      cmd.review
    end
  end

  # ──────────────────────────────────────────────────────────
  # approve
  # ──────────────────────────────────────────────────────────

  describe '#approve' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'succeeds for known extension' do
      expect(out).to receive(:success).with(/'lex-test' approved/)
      build_command(notes: nil).approve('lex-test')
    end

    it 'sets status to approved in registry' do
      build_command(notes: nil).approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:approved)
    end

    it 'stores notes when provided' do
      build_command(notes: 'LGTM').approve('lex-test')
      expect(Legion::Registry.lookup('lex-test').review_notes).to eq('LGTM')
    end

    it 'errors for unknown extension' do
      expect(out).to receive(:error).with(/not found/)
      build_command(notes: nil).approve('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true, notes: nil)
      expect(out).to receive(:json).with(hash_including(status: 'approved'))
      cmd.approve('lex-test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # reject
  # ──────────────────────────────────────────────────────────

  describe '#reject' do
    before { Legion::Registry.submit_for_review('lex-test') }

    it 'succeeds for known extension' do
      expect(out).to receive(:success).with(/'lex-test' rejected/)
      build_command(reason: nil).reject('lex-test')
    end

    it 'sets status to rejected in registry' do
      build_command(reason: nil).reject('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:rejected)
    end

    it 'stores reason when provided' do
      build_command(reason: 'CVE found').reject('lex-test')
      expect(Legion::Registry.lookup('lex-test').reject_reason).to eq('CVE found')
    end

    it 'errors for unknown extension' do
      expect(out).to receive(:error).with(/not found/)
      build_command(reason: nil).reject('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true, reason: nil)
      expect(out).to receive(:json).with(hash_including(status: 'rejected'))
      cmd.reject('lex-test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # deprecate
  # ──────────────────────────────────────────────────────────

  describe '#deprecate' do
    it 'succeeds for known extension' do
      expect(out).to receive(:success).with(/deprecated/)
      build_command(successor: nil, sunset_date: nil).deprecate('lex-test')
    end

    it 'sets status to deprecated in registry' do
      build_command(successor: nil, sunset_date: nil).deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').status).to eq(:deprecated)
    end

    it 'stores successor when provided' do
      build_command(successor: 'lex-test-v2', sunset_date: nil).deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').successor).to eq('lex-test-v2')
    end

    it 'parses sunset_date when provided' do
      build_command(successor: nil, sunset_date: '2027-01-01').deprecate('lex-test')
      expect(Legion::Registry.lookup('lex-test').sunset_date).to eq(Date.new(2027, 1, 1))
    end

    it 'errors for unknown extension' do
      expect(out).to receive(:error).with(/not found/)
      build_command(successor: nil, sunset_date: nil).deprecate('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true, successor: nil, sunset_date: nil)
      expect(out).to receive(:json).with(hash_including(status: 'deprecated'))
      cmd.deprecate('lex-test')
    end
  end

  # ──────────────────────────────────────────────────────────
  # install
  # ──────────────────────────────────────────────────────────

  describe '#install' do
    it 'rejects names that do not start with lex-' do
      expect(out).to receive(:error).with(/must start with 'lex-'/)
      build_command.install('my-gem')
    end

    it 'calls gem install for a valid lex name' do
      allow(Kernel).to receive(:system).and_return(true)
      expect(Kernel).to receive(:system).with('gem', 'install', 'lex-foo').and_return(true)
      build_command.install('lex-foo')
    end

    it 'reports success when install succeeds' do
      allow(Kernel).to receive(:system).and_return(true)
      expect(out).to receive(:success).with(/'lex-foo' installed successfully/)
      build_command.install('lex-foo')
    end

    it 'reports error when install fails' do
      allow(Kernel).to receive(:system).and_return(false)
      expect(out).to receive(:error).with(/Failed to install/)
      build_command.install('lex-foo')
    end
  end

  # ──────────────────────────────────────────────────────────
  # publish
  # ──────────────────────────────────────────────────────────

  describe '#publish' do
    before do
      allow(Kernel).to receive(:system).and_return(true)
      allow(Dir).to receive(:glob).with('*.gemspec').and_return(['lex-foo.gemspec'])
      allow(Dir).to receive(:glob).with('lex-foo-*.gem').and_return(['lex-foo-1.0.0.gem'])
      allow(File).to receive(:mtime).with('lex-foo-1.0.0.gem').and_return(Time.now)
      allow(Legion::Registry::SecurityScanner).to receive(:new).and_return(
        instance_double(Legion::Registry::SecurityScanner, scan: { passed: true, checks: [] })
      )
    end

    it 'errors when no gemspec found' do
      allow(Dir).to receive(:glob).with('*.gemspec').and_return([])
      expect(out).to receive(:error).with(/no gemspec found/i)
      build_command.publish
    end

    it 'errors when rspec fails' do
      allow(Kernel).to receive(:system).with('bundle', 'exec', 'rspec').and_return(false)
      expect(out).to receive(:error).with(/specs failed/i)
      build_command.publish
    end

    it 'errors when rubocop fails' do
      allow(Kernel).to receive(:system).with('bundle', 'exec', 'rspec').and_return(true)
      allow(Kernel).to receive(:system).with('bundle', 'exec', 'rubocop').and_return(false)
      expect(out).to receive(:error).with(/rubocop failed/i)
      build_command.publish
    end

    it 'builds and pushes gem on success' do
      expect(Kernel).to receive(:system).with('bundle', 'exec', 'rspec').and_return(true)
      expect(Kernel).to receive(:system).with('bundle', 'exec', 'rubocop').and_return(true)
      expect(Kernel).to receive(:system).with('gem', 'build', 'lex-foo.gemspec').and_return(true)
      expect(Kernel).to receive(:system).with('gem', 'push', 'lex-foo-1.0.0.gem').and_return(true)
      expect(out).to receive(:success).with(/published/)
      build_command.publish
    end
  end

  # ──────────────────────────────────────────────────────────
  # stats
  # ──────────────────────────────────────────────────────────

  describe '#stats' do
    it 'shows header and detail for known extension' do
      expect(out).to receive(:header).with(/lex-test/)
      expect(out).to receive(:detail).with(hash_including('Install Count'))
      build_command.stats('lex-test')
    end

    it 'errors for unknown extension' do
      expect(out).to receive(:error).with(/not found/)
      build_command.stats('lex-missing')
    end

    it 'outputs json when --json is set' do
      cmd = build_command(json: true)
      expect(out).to receive(:json).with(hash_including(name: 'lex-test'))
      cmd.stats('lex-test')
    end
  end
end
