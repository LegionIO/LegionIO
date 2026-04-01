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

  describe '.parse_rb' do
    it 'parses a Ruby skill file with comment metadata' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'my_tool.rb')
        File.write(path, "# description: Does something useful\n# model: claude-sonnet\ndef self.call(input:)\n  input\nend")
        result = described_class.parse_rb(path)
        expect(result[:name]).to eq('my_tool')
        expect(result[:description]).to eq('Does something useful')
        expect(result[:model]).to eq('claude-sonnet')
        expect(result[:type]).to eq(:ruby)
      end
    end

    it 'defaults description to empty string' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bare.rb')
        File.write(path, "def self.call(input:)\n  'hello'\nend")
        result = described_class.parse_rb(path)
        expect(result[:description]).to eq('')
        expect(result[:type]).to eq(:ruby)
      end
    end
  end

  describe '.discover with mixed file types' do
    it 'discovers both .md and .rb skills' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'prompt.md'), "---\nname: prompt\n---\nDo things.")
        File.write(File.join(dir, 'script.rb'), "# description: A ruby skill\ndef self.call(input:)\n  input\nend")

        stub_const('Legion::Chat::Skills::SKILL_DIRS', [dir])
        skills = described_class.discover
        expect(skills.map { |s| s[:name] }).to contain_exactly('prompt', 'script')
        expect(skills.map { |s| s[:type] }).to contain_exactly(:prompt, :ruby)
      end
    end
  end

  describe '.execute' do
    it 'returns error for unknown skill type' do
      skill = { type: :unknown, name: 'bad' }
      result = described_class.execute(skill)
      expect(result[:success]).to be false
      expect(result[:error]).to include('unknown skill type')
    end

    it 'returns error for prompt skill when LLM is not available' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      skill = { type: :prompt, name: 'test', prompt: 'hello', model: nil }
      result = described_class.execute(skill)
      expect(result[:success]).to be false
      expect(result[:error]).to include('LLM not available')
    end

    it 'executes a ruby skill with self.call' do
      Dir.mktmpdir do |dir|
        stub_const('Legion::Chat::Skills::SKILL_DIRS', [dir])
        path = File.join(dir, 'adder.rb')
        File.write(path, "def self.call(input:)\n  \"got: \#{input}\"\nend")
        skill = { type: :ruby, name: 'adder', path: path }
        result = described_class.execute(skill, input: 'test')
        expect(result[:success]).to be true
        expect(result[:output]).to eq('got: test')
      end
    end

    it 'returns error when ruby skill has no self.call' do
      Dir.mktmpdir do |dir|
        stub_const('Legion::Chat::Skills::SKILL_DIRS', [dir])
        path = File.join(dir, 'nocall.rb')
        File.write(path, "HELLO = 'world'")
        skill = { type: :ruby, name: 'nocall', path: path }
        result = described_class.execute(skill)
        expect(result[:success]).to be false
        expect(result[:error]).to include('self.call')
      end
    end

    it 'rejects skill paths outside allowed directories' do
      Dir.mktmpdir do |dir|
        stub_const('Legion::Chat::Skills::SKILL_DIRS', [dir])
        other_dir = Dir.mktmpdir
        path = File.join(other_dir, 'evil.rb')
        File.write(path, "def self.call(input:)\n  'pwned'\nend")
        skill = { type: :ruby, name: 'evil', path: path }
        result = described_class.execute(skill)
        expect(result[:success]).to be false
        expect(result[:error]).to include('outside allowed directories')
        FileUtils.remove_entry(other_dir)
      end
    end
  end
end
