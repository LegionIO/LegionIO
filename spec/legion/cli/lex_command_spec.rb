# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'legion/cli'
require 'legion/cli/lex_command'

RSpec.describe Legion::CLI::Lex do
  let(:out) { instance_double(Legion::CLI::Output::Formatter) }

  before do
    allow(Legion::CLI::Output::Formatter).to receive(:new).and_return(out)
    allow(out).to receive(:success)
    allow(out).to receive(:error)
    allow(out).to receive(:warn)
    allow(out).to receive(:spacer)
    allow(Dir).to receive(:exist?).and_return(false)
    allow(Dir).to receive(:pwd).and_return('/tmp')
  end

  def build_lex(opts = {})
    described_class.new([], { json: false, no_color: true }.merge(opts))
  end

  describe '#create' do
    describe 'category format validation' do
      it 'outputs an error and returns early when category contains uppercase letters' do
        expect(Legion::Extensions).not_to receive(:check_reserved_words)
        expect(Legion::CLI::LexGenerator).not_to receive(:new)

        lex = build_lex(category: 'My Category')
        lex.create('anchor')

        expect(out).to have_received(:error).with('--category must be lowercase letters, numbers, underscores, or hyphens')
      end

      it 'accepts a valid lowercase category' do
        expect(Legion::Extensions).to receive(:check_reserved_words)
        allow(Legion::CLI::LexGenerator).to receive(:new).and_return(double(generate: nil))

        lex = build_lex(category: 'agentic')
        lex.create('anchor')
      end
    end

    describe 'reserved word warning' do
      it 'calls check_reserved_words on the derived gem name when category is given' do
        expect(Legion::Extensions).to receive(:check_reserved_words)
          .with('lex-agentic-cognitive-anchor', known_org: false)
        allow(Legion::CLI::LexGenerator).to receive(:new).and_return(double(generate: nil))

        lex = build_lex(category: 'agentic')
        lex.create('cognitive-anchor')
      end

      it 'calls check_reserved_words with plain gem name when no category given' do
        expect(Legion::Extensions).to receive(:check_reserved_words)
          .with('lex-mycustomext', known_org: false)
        allow(Legion::CLI::LexGenerator).to receive(:new).and_return(double(generate: nil))

        lex = build_lex
        lex.create('mycustomext')
      end
    end
  end
end

RSpec.describe Legion::CLI::LexGenerator do
  let(:base_options) do
    { rspec: false, github_ci: false, git_init: false, bundle_install: false }
  end

  describe 'flat (no category) scaffolding' do
    let(:name) { 'myext' }
    let(:gem_name) { 'lex-myext' }
    let(:vars) { { filename: gem_name, class_name: 'Myext', lex: name } }
    subject(:generator) { described_class.new(name, vars, base_options) }

    it 'derives a flat gem name' do
      expect(generator.send(:gem_name)).to eq('lex-myext')
    end

    it 'generates a flat module declaration' do
      content = generator.send(:extension_entry_content)
      expect(content).to include('module Legion')
      expect(content).to include('module Extensions')
      expect(content).to include('module Myext')
    end

    it 'generates a flat version constant' do
      content = generator.send(:version_content)
      expect(content).to include('module Myext')
      expect(content).to include("VERSION = '0.1.0'")
    end

    it 'generates a flat require path in spec_helper' do
      content = generator.send(:spec_helper_content)
      expect(content).to include("require 'legion/extensions/myext'")
    end

    it 'generates a flat RSpec describe block' do
      content = generator.send(:spec_content)
      expect(content).to include('Legion::Extensions::Myext')
    end

    it 'uses flat target directory' do
      expect(generator.send(:target_dir)).to eq('lex-myext')
    end
  end

  describe 'nested (with --category) scaffolding' do
    let(:name) { 'cognitive-anchor' }
    let(:category) { 'agentic' }
    let(:gem_name) { 'lex-agentic-cognitive-anchor' }
    let(:vars) { { filename: gem_name, class_name: 'CognitiveAnchor', lex: name } }
    let(:options) { base_options.merge(category: category) }
    subject(:generator) { described_class.new(name, vars, options, gem_name: gem_name) }

    it 'uses the full categorized gem name' do
      expect(generator.send(:gem_name)).to eq('lex-agentic-cognitive-anchor')
    end

    it 'generates nested module declaration' do
      content = generator.send(:extension_entry_content)
      expect(content).to include('module Agentic')
      expect(content).to include('module Cognitive')
      expect(content).to include('module Anchor')
    end

    it 'generates nested version constant' do
      content = generator.send(:version_content)
      expect(content).to include('module Agentic')
      expect(content).to include('module Cognitive')
      expect(content).to include('module Anchor')
      expect(content).to include("VERSION = '0.1.0'")
    end

    it 'generates nested require path in spec_helper' do
      content = generator.send(:spec_helper_content)
      expect(content).to include("require 'legion/extensions/agentic/cognitive/anchor'")
    end

    it 'generates nested RSpec describe block' do
      content = generator.send(:spec_content)
      expect(content).to include('Legion::Extensions::Agentic::Cognitive::Anchor')
    end

    it 'uses nested target directory' do
      expect(generator.send(:target_dir)).to eq('lex-agentic-cognitive-anchor')
    end

    it 'generates correct nested dir path for extension entry' do
      # The entry file should be at the nested require path
      dirs = generator.send(:extension_dirs)
      expect(dirs).to include('lex-agentic-cognitive-anchor/lib/legion/extensions/agentic/cognitive/anchor')
    end
  end

  describe 'nested module content structure' do
    let(:name) { 'cognitive-anchor' }
    let(:gem_name) { 'lex-agentic-cognitive-anchor' }
    let(:vars) { { filename: gem_name, class_name: 'CognitiveAnchor', lex: name } }
    let(:options) { base_options.merge(category: 'agentic') }
    subject(:generator) { described_class.new(name, vars, options, gem_name: gem_name) }

    it 'module nesting opens outer-to-inner and closes inner-to-outer' do
      content = generator.send(:extension_entry_content)
      agentic_pos = content.index('module Agentic')
      cognitive_pos = content.index('module Cognitive')
      anchor_pos = content.index('module Anchor')
      expect(agentic_pos).to be < cognitive_pos
      expect(cognitive_pos).to be < anchor_pos
    end
  end
end
