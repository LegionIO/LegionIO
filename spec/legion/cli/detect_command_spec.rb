# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/detect_command'

RSpec.describe Legion::CLI::Detect do
  let(:scan_results) do
    [
      {
        name:            'Claude',
        extensions:      ['lex-claude'],
        matched_signals: ['app:Claude.app', 'brew_cask:claude'],
        installed:       { 'lex-claude' => true }
      },
      {
        name:            'Slack',
        extensions:      ['lex-slack'],
        matched_signals: ['app:Slack.app'],
        installed:       { 'lex-slack' => false }
      },
      {
        name:            'Redis',
        extensions:      %w[lex-redis legion-cache],
        matched_signals: ['brew_formula:redis'],
        installed:       { 'lex-redis' => false, 'legion-cache' => true }
      }
    ]
  end

  let(:catalog) do
    [
      { name: 'Claude', extensions: ['lex-claude'], signals: [{ type: :app, match: 'Claude.app' }] },
      { name: 'Slack', extensions: ['lex-slack'], signals: [{ type: :app, match: 'Slack.app' }] }
    ]
  end

  before do
    detect_mod = Module.new do
      def self.scan; end
      def self.missing; end
      def self.catalog; end
      def self.install_missing!(**); end
    end
    stub_const('Legion::Extensions::Detect', detect_mod)
    allow(Legion::Extensions::Detect).to receive(:scan).and_return(scan_results)
    allow(Legion::Extensions::Detect).to receive(:missing).and_return(%w[lex-slack lex-redis])
    allow(Legion::Extensions::Detect).to receive(:catalog).and_return(catalog)
    allow(Legion::Extensions::Detect).to receive(:install_missing!)
      .and_return({ installed: %w[lex-slack lex-redis], failed: [] })

    # Stub the require so it doesn't fail (gem not in bundle).
    # Thor warns about the method stub but it's harmless in tests.
    allow_any_instance_of(described_class).to receive(:require_detect_gem)
  end

  describe 'scan' do
    it 'displays detection results' do
      output = capture_stdout { described_class.start(%w[scan --no-color]) }
      expect(output).to include('Claude')
      expect(output).to include('Slack')
      expect(output).to include('installed')
      expect(output).to include('missing')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[scan --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:detections]).to be_an(Array)
      expect(parsed[:detections].size).to eq(3)
    end

    it 'installs missing when --install is passed' do
      capture_stdout { described_class.start(%w[scan --install --no-color]) }
      expect(Legion::Extensions::Detect).to have_received(:install_missing!)
    end
  end

  describe 'catalog' do
    it 'displays the catalog' do
      output = capture_stdout { described_class.start(%w[catalog --no-color]) }
      expect(output).to include('Claude')
      expect(output).to include('Slack')
      expect(output).to include('Detection Catalog')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[catalog --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:catalog]).to be_an(Array)
    end
  end

  describe 'missing' do
    it 'lists missing extensions' do
      output = capture_stdout { described_class.start(%w[missing --no-color]) }
      expect(output).to include('lex-slack')
      expect(output).to include('lex-redis')
    end

    it 'outputs JSON when --json is passed' do
      output = capture_stdout { described_class.start(%w[missing --json]) }
      parsed = JSON.parse(output, symbolize_names: true)
      expect(parsed[:missing]).to eq(%w[lex-slack lex-redis])
    end

    it 'shows success when nothing is missing' do
      allow(Legion::Extensions::Detect).to receive(:missing).and_return([])
      output = capture_stdout { described_class.start(%w[missing --no-color]) }
      expect(output).to include('All detected extensions are installed')
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
