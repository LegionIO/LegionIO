# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/output_styles'

RSpec.describe Legion::CLI::Chat::OutputStyles do
  let(:tmpdir) { Dir.mktmpdir }

  before do
    stub_const('Legion::CLI::Chat::OutputStyles::STYLE_DIRS', [tmpdir])
  end

  after { FileUtils.rm_rf(tmpdir) }

  def write_style(name, frontmatter, body)
    fm = frontmatter.map { |k, v| v.is_a?(String) ? "#{k}: \"#{v}\"" : "#{k}: #{v}" }.join("\n")
    File.write(File.join(tmpdir, "#{name}.md"), "---\n#{fm}\n---\n\n#{body}")
  end

  describe '.discover' do
    it 'returns empty when no style dirs exist' do
      stub_const('Legion::CLI::Chat::OutputStyles::STYLE_DIRS', ['/nonexistent'])
      expect(described_class.discover).to eq([])
    end

    it 'discovers .md style files' do
      write_style('concise', { name: 'concise', description: 'Brief responses', active: true }, 'Be concise.')
      write_style('verbose', { name: 'verbose', description: 'Detailed responses', active: false }, 'Be verbose.')

      styles = described_class.discover
      expect(styles.map { |s| s[:name] }).to contain_exactly('concise', 'verbose')
    end
  end

  describe '.parse' do
    it 'parses frontmatter and body' do
      write_style('test', { name: 'test-style', description: 'A test', active: true }, 'Style body here.')
      result = described_class.parse(File.join(tmpdir, 'test.md'))
      expect(result[:name]).to eq('test-style')
      expect(result[:description]).to eq('A test')
      expect(result[:active]).to be true
      expect(result[:content]).to eq('Style body here.')
    end

    it 'defaults name from filename' do
      File.write(File.join(tmpdir, 'unnamed.md'), "---\ndescription: no name\n---\n\nbody")
      result = described_class.parse(File.join(tmpdir, 'unnamed.md'))
      expect(result[:name]).to eq('unnamed')
    end

    it 'returns nil for non-frontmatter files' do
      File.write(File.join(tmpdir, 'plain.md'), 'just text')
      expect(described_class.parse(File.join(tmpdir, 'plain.md'))).to be_nil
    end
  end

  describe '.active_styles' do
    it 'returns only active styles' do
      write_style('on', { name: 'on', active: true }, 'active style')
      write_style('off', { name: 'off', active: false }, 'inactive style')

      active = described_class.active_styles
      expect(active.map { |s| s[:name] }).to eq(['on'])
    end
  end

  describe '.find' do
    it 'finds a style by name' do
      write_style('target', { name: 'target', description: 'found it' }, 'body')
      expect(described_class.find('target')[:description]).to eq('found it')
    end

    it 'returns nil for missing style' do
      expect(described_class.find('nonexistent')).to be_nil
    end
  end

  describe '.system_prompt_injection' do
    it 'returns nil when no active styles' do
      write_style('inactive', { name: 'inactive', active: false }, 'nope')
      expect(described_class.system_prompt_injection).to be_nil
    end

    it 'returns concatenated content of active styles' do
      write_style('a', { name: 'a', active: true }, 'Style A content')
      write_style('b', { name: 'b', active: true }, 'Style B content')

      result = described_class.system_prompt_injection
      expect(result).to include('Style A content')
      expect(result).to include('Style B content')
    end
  end
end
