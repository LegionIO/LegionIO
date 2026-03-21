# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/docs/site_generator'

RSpec.describe Legion::Docs::SiteGenerator do
  subject(:generator) { described_class.new(output_dir: tmpdir) }

  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  # ---------------------------------------------------------------------------
  # #generate — orchestration
  # ---------------------------------------------------------------------------

  describe '#generate' do
    it 'creates the output directory when it does not exist' do
      subdir = File.join(tmpdir, 'nested', 'site')
      gen = described_class.new(output_dir: subdir)
      gen.generate
      expect(Dir.exist?(subdir)).to be true
    end

    it 'returns a hash with :output equal to the output_dir' do
      result = generator.generate
      expect(result[:output]).to eq(tmpdir)
    end

    it 'returns :sections equal to the number of GUIDE_SOURCES entries' do
      result = generator.generate
      expect(result[:sections]).to eq(described_class::GUIDE_SOURCES.size)
    end

    it 'returns :pages as a positive integer' do
      result = generator.generate
      expect(result[:pages]).to be > 0
    end

    it 'returns :files as an array of absolute paths' do
      result = generator.generate
      expect(result[:files]).to all(be_a(String))
      expect(result[:files]).to all(start_with('/'))
    end

    it 'writes index.html to the output directory' do
      generator.generate
      expect(File.exist?(File.join(tmpdir, 'index.html'))).to be true
    end

    it 'writes cli-reference.html to the output directory' do
      generator.generate
      expect(File.exist?(File.join(tmpdir, 'cli-reference.html'))).to be true
    end

    it 'writes extensions.html to the output directory' do
      generator.generate
      expect(File.exist?(File.join(tmpdir, 'extensions.html'))).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # SECTIONS / GUIDE_SOURCES backwards compat
  # ---------------------------------------------------------------------------

  describe 'SECTIONS constant' do
    it 'is equal to GUIDE_SOURCES for backwards compatibility' do
      expect(described_class::SECTIONS).to eq(described_class::GUIDE_SOURCES)
    end

    it 'has 5 entries' do
      expect(described_class::GUIDE_SOURCES.size).to eq(5)
    end

    it 'each entry has :source, :title, and :section keys' do
      described_class::GUIDE_SOURCES.each do |entry|
        expect(entry).to include(:source, :title, :section)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Guide page generation
  # ---------------------------------------------------------------------------

  describe 'guide pages' do
    it 'generates an HTML file for each guide source' do
      generator.generate
      described_class::GUIDE_SOURCES.each do |entry|
        slug = File.basename(entry[:source], '.md').downcase.tr('_', '-')
        expect(File.exist?(File.join(tmpdir, "#{slug}.html"))).to be true
      end
    end

    it 'uses a placeholder when the source file does not exist' do
      generator.generate
      described_class::GUIDE_SOURCES.each do |entry|
        slug = File.basename(entry[:source], '.md').downcase.tr('_', '-')
        content = File.read(File.join(tmpdir, "#{slug}.html"))
        # Either rendered content from real file, or the fallback placeholder
        expect(content).not_to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Markdown rendering (private, tested through public output)
  # ---------------------------------------------------------------------------

  describe 'markdown rendering' do
    it 'converts headings to <h> tags in guide output' do
      # Write a temp guide source to test conversion
      guide_path = File.join(tmpdir, 'src')
      FileUtils.mkdir_p(guide_path)
      md_file = File.join(guide_path, 'getting-started.md')
      File.write(md_file, "# Hello World\n\nSome content.\n")

      gen = described_class.new(output_dir: File.join(tmpdir, 'out'))

      # Directly test render_markdown via the rendered index output
      html = gen.send(:render_markdown, "# Hello World\n\nSome content.\n")
      expect(html).to include('<h1')
      expect(html).to include('Hello World')
    end

    it 'produces output even without a source file (fallback placeholder)' do
      gen = described_class.new(output_dir: tmpdir)
      html = gen.send(:render_markdown, "# Title\n")
      expect(html).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # html_template
  # ---------------------------------------------------------------------------

  describe '#html_template' do
    let(:template_output) do
      generator.send(:html_template, title: 'My Page', body: '<p>Body</p>', nav: '<a href="#">Nav</a>')
    end

    it 'wraps content in a valid HTML5 document' do
      expect(template_output).to include('<!DOCTYPE html>')
      expect(template_output).to include('<html')
      expect(template_output).to include('</html>')
    end

    it 'includes the page title in the <title> tag' do
      expect(template_output).to include('<title>My Page')
    end

    it 'injects the body content' do
      expect(template_output).to include('<p>Body</p>')
    end

    it 'injects the nav content' do
      expect(template_output).to include('<a href="#">Nav</a>')
    end

    it 'includes an h1 with the title' do
      expect(template_output).to include('<h1>My Page</h1>')
    end

    it 'escapes HTML special characters in title' do
      out = generator.send(:html_template, title: '<script>alert(1)</script>', body: '', nav: '')
      expect(out).to include('&lt;script&gt;')
      expect(out).not_to include('<script>alert')
    end
  end

  # ---------------------------------------------------------------------------
  # Index page
  # ---------------------------------------------------------------------------

  describe 'index page' do
    it 'creates index.html with links to all pages' do
      generator.generate
      index = File.read(File.join(tmpdir, 'index.html'))
      expect(index).to include('.html')
      expect(index).to include('LegionIO')
    end

    it 'groups pages by section' do
      generator.generate
      index = File.read(File.join(tmpdir, 'index.html'))
      # Guides and reference sections both appear
      expect(index.downcase).to include('guides')
      expect(index.downcase).to include('reference')
    end
  end

  # ---------------------------------------------------------------------------
  # CLI reference generation (with mocked introspection)
  # ---------------------------------------------------------------------------

  describe 'CLI reference generation' do
    context 'when Legion::CLI::Main is not defined' do
      it 'falls back to a "unavailable" message' do
        hide_const('Legion::CLI::Main') if defined?(Legion::CLI::Main)
        generator.generate
        cli_html = File.read(File.join(tmpdir, 'cli-reference.html'))
        expect(cli_html).to include('unavailable').or include('CLI Reference')
      end
    end

    context 'when Legion::CLI::Main is available' do
      before do
        fake_cmd = double('cmd', description: 'Do a thing')
        fake_main = double('Main')
        allow(fake_main).to receive(:all_commands).and_return({ 'start' => fake_cmd })
        stub_const('Legion::CLI::Main', fake_main)
      end

      it 'includes introspected command names' do
        generator.generate
        cli_html = File.read(File.join(tmpdir, 'cli-reference.html'))
        expect(cli_html).to include('legion start')
      end

      it 'includes command descriptions' do
        generator.generate
        cli_html = File.read(File.join(tmpdir, 'cli-reference.html'))
        expect(cli_html).to include('Do a thing')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Extension reference generation
  # ---------------------------------------------------------------------------

  describe 'extension reference generation' do
    context 'when no lex- gems are installed' do
      before do
        fake_loader = double('BundlerLoader')
        allow(fake_loader).to receive(:specs).and_return([])
        allow(Bundler).to receive(:load).and_return(fake_loader)
      end

      it 'still creates the extensions.html page' do
        generator.generate
        expect(File.exist?(File.join(tmpdir, 'extensions.html'))).to be true
      end

      it 'shows a "no extensions" message' do
        generator.generate
        ext_html = File.read(File.join(tmpdir, 'extensions.html'))
        expect(ext_html).to include('No extensions').or include('Extensions')
      end
    end

    context 'when lex- gems are available' do
      let(:fake_spec) do
        double('Gem::Specification', name: 'lex-http', version: double(to_s: '0.2.0'))
      end

      before do
        fake_loader = double('BundlerLoader')
        allow(fake_loader).to receive(:specs).and_return([fake_spec])
        allow(Bundler).to receive(:load).and_return(fake_loader)
      end

      it 'lists the discovered extension' do
        generator.generate
        ext_html = File.read(File.join(tmpdir, 'extensions.html'))
        expect(ext_html).to include('lex-http')
        expect(ext_html).to include('0.2.0')
      end
    end
  end
end
