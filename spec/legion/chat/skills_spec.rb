# frozen_string_literal: true

require 'spec_helper'
require 'legion/chat/skills'
require 'tmpdir'

RSpec.describe Legion::Chat::Skills do
  describe '.parse' do
    it 'parses valid skill file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.md')
        File.write(path, "---\nname: test-skill\ndescription: A test\nmodel: gpt-4o\ntools:\n  - read_file\n---\nYou are a test assistant.")

        result = described_class.parse(path)
        expect(result[:name]).to eq('test-skill')
        expect(result[:description]).to eq('A test')
        expect(result[:model]).to eq('gpt-4o')
        expect(result[:tools]).to eq(['read_file'])
        expect(result[:prompt]).to eq('You are a test assistant.')
      end
    end

    it 'returns nil for non-frontmatter file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'plain.md')
        File.write(path, 'Just a regular markdown file')
        expect(described_class.parse(path)).to be_nil
      end
    end

    it 'defaults name from filename' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'my-skill.md')
        File.write(path, "---\ndescription: No name field\n---\nPrompt body.")

        result = described_class.parse(path)
        expect(result[:name]).to eq('my-skill')
      end
    end

    it 'handles empty tools list' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'minimal.md')
        File.write(path, "---\nname: minimal\n---\nDo something.")

        result = described_class.parse(path)
        expect(result[:tools]).to eq([])
      end
    end
  end

  describe '.discover' do
    it 'returns empty array when no skill dirs exist' do
      stub_const('Legion::Chat::Skills::SKILL_DIRS', ['/nonexistent/path'])
      expect(described_class.discover).to eq([])
    end

    it 'discovers skills from existing directory' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'one.md'), "---\nname: one\n---\nFirst.")
        File.write(File.join(dir, 'two.md'), "---\nname: two\n---\nSecond.")
        File.write(File.join(dir, 'plain.txt'), 'Not a skill')

        stub_const('Legion::Chat::Skills::SKILL_DIRS', [dir])
        skills = described_class.discover
        expect(skills.map { |s| s[:name] }).to contain_exactly('one', 'two')
      end
    end
  end

  describe '.find' do
    it 'returns nil when skill not found' do
      allow(described_class).to receive(:discover).and_return([])
      expect(described_class.find('nonexistent')).to be_nil
    end

    it 'finds skill by name' do
      skill = { name: 'target', prompt: 'hello' }
      allow(described_class).to receive(:discover).and_return([skill])
      expect(described_class.find('target')).to eq(skill)
    end
  end
end
