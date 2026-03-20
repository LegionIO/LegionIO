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

    describe '--template option' do
      it 'passes the template name to LexGenerator' do
        expect(Legion::Extensions).to receive(:check_reserved_words)
        gen = double(generate: nil)
        expect(Legion::CLI::LexGenerator).to receive(:new)
          .with('myext', anything, anything, gem_name: 'lex-myext', template: 'llm-agent')
          .and_return(gen)

        lex = build_lex(template: 'llm-agent')
        lex.create('myext')
      end

      it 'falls back to basic and warns on unknown template' do
        allow(Legion::Extensions).to receive(:check_reserved_words)
        allow(Legion::CLI::LexGenerator).to receive(:new).and_return(double(generate: nil))
        expect(out).to receive(:warn).with(/unknown template/i)

        lex = build_lex(template: 'nonexistent-template')
        lex.create('myext')
      end

      it 'uses basic template by default' do
        expect(Legion::Extensions).to receive(:check_reserved_words)
        gen = double(generate: nil)
        expect(Legion::CLI::LexGenerator).to receive(:new)
          .with('myext', anything, anything, gem_name: 'lex-myext', template: 'basic')
          .and_return(gen)

        lex = build_lex
        lex.create('myext')
      end
    end

    describe '--list-templates option' do
      it 'outputs the template list and returns without creating anything' do
        expect(Legion::CLI::LexGenerator).not_to receive(:new)
        allow(out).to receive(:header)
        allow(out).to receive(:table)

        lex = build_lex(list_templates: true)
        lex.create
      end

      it 'renders a table with template info' do
        expect(out).to receive(:header).with(/template/i)
        expect(out).to receive(:table) do |headers, rows|
          expect(headers).to include('template')
          expect(headers).to include('description')
          expect(rows).not_to be_empty
        end

        lex = build_lex(list_templates: true)
        lex.create
      end
    end

    describe 'when NAME is omitted without --list-templates' do
      it 'outputs an error and returns' do
        expect(Legion::CLI::LexGenerator).not_to receive(:new)
        expect(out).to receive(:error).with(/NAME is required/)

        lex = build_lex
        lex.create
      end
    end
  end

  describe '#discover_all' do
    let(:fake_spec) do
      instance_double(
        Gem::Specification,
        name:                 'lex-node',
        version:              Gem::Version.new('0.2.3'),
        gem_dir:              '/fake/gem/dir',
        runtime_dependencies: []
      )
    end

    before do
      allow(Gem::Specification).to receive(:select).and_return([fake_spec])
      allow(Legion::CLI::Connection).to receive(:ensure_settings)
      allow(Legion::Settings).to receive(:[]).with(:extensions).and_return({})
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      allow(Dir).to receive(:exist?).with('/fake/gem/dir/lib/legion/extensions/node/runners').and_return(false)
      allow(Dir).to receive(:exist?).with('/fake/gem/dir/lib/legion/extensions/node/actors').and_return(false)
    end

    it 'includes :category key in each extension info hash' do
      lex = build_lex
      results = lex.discover_all
      expect(results.first).to have_key(:category)
    end

    it 'includes :tier key in each extension info hash' do
      lex = build_lex
      results = lex.discover_all
      expect(results.first).to have_key(:tier)
    end

    it 'categorizes lex-node as core when core list contains it' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :categories).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:extensions, :core).and_return(['lex-node'])
      allow(Legion::Settings).to receive(:dig).with(:extensions, :ai).and_return([])
      allow(Legion::Settings).to receive(:dig).with(:extensions, :gaia).and_return([])

      lex = build_lex
      results = lex.discover_all
      expect(results.first[:category]).to eq('core')
      expect(results.first[:tier]).to eq(1)
    end

    it 'uses :default category when gem is not in any list and has no matching prefix' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :categories).and_return(nil)
      allow(Legion::Settings).to receive(:dig).with(:extensions, :core).and_return([])
      allow(Legion::Settings).to receive(:dig).with(:extensions, :ai).and_return([])
      allow(Legion::Settings).to receive(:dig).with(:extensions, :gaia).and_return([])

      lex = build_lex
      results = lex.discover_all
      expect(results.first[:category]).to eq('default')
    end
  end

  describe '#list' do
    let(:fake_extensions) do
      [
        { name: 'node',        version: '0.2.3', status: 'installed', category: 'core',    tier: 1, runners: [], actors: [] },
        { name: 'agentic-foo', version: '0.1.0', status: 'installed', category: 'agentic', tier: 4, runners: [], actors: [] },
        { name: 'openai',      version: '0.1.0', status: 'installed', category: 'ai',      tier: 2, runners: [], actors: [] },
        { name: 'custom-ext',  version: '0.1.0', status: 'installed', category: 'default', tier: 5, runners: [], actors: [] }
      ]
    end

    before do
      allow(out).to receive(:status).and_return('installed')
      allow(out).to receive(:table)
      allow(out).to receive(:header)
      lex = build_lex
      allow(lex).to receive(:discover_all).and_return(fake_extensions)
      @lex = lex
    end

    it 'groups output by category when no args and no --flat' do
      expect(out).to receive(:header).at_least(:once)
      @lex.list
    end

    it 'renders a header for the default (tier 5) category in grouped mode' do
      expect(out).to receive(:header).with(/default.*tier 5/i)
      @lex.list
    end

    it 'filters to a specific category when argument is given' do
      expect(out).to receive(:table) do |_headers, rows|
        names = rows.map(&:first)
        expect(names).to all(eq('agentic-foo'))
      end
      @lex.list('agentic')
    end

    it 'shows all extensions in a flat table when --flat is given' do
      lex = build_lex(flat: true)
      allow(lex).to receive(:discover_all).and_return(fake_extensions)
      expect(out).to receive(:table) do |_headers, rows|
        expect(rows.length).to eq(4)
      end
      lex.list
    end

    it 'includes category column in flat mode table headers' do
      lex = build_lex(flat: true)
      allow(lex).to receive(:discover_all).and_return(fake_extensions)
      expect(out).to receive(:table) do |headers, _rows|
        expect(headers).to include('category')
      end
      lex.list
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
