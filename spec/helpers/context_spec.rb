# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/helpers/context'

RSpec.describe Legion::Helpers::Context do
  let(:tmpdir) { Dir.mktmpdir('legion-context-test') }

  before do
    allow(described_class).to receive(:context_dir).and_return(tmpdir)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.write' do
    it 'writes content to agent subdirectory' do
      result = described_class.write(agent_id: 'agent-a', filename: 'plan.md', content: '# My Plan')
      expect(result[:success]).to be true
      expect(File.exist?(File.join(tmpdir, 'agent-a', 'plan.md'))).to be true
      expect(File.read(File.join(tmpdir, 'agent-a', 'plan.md'))).to eq('# My Plan')
    end

    it 'creates nested directories' do
      result = described_class.write(agent_id: 'agent-b', filename: 'sub/deep/file.txt', content: 'hello')
      expect(result[:success]).to be true
      expect(File.exist?(File.join(tmpdir, 'agent-b', 'sub', 'deep', 'file.txt'))).to be true
    end
  end

  describe '.read' do
    it 'reads content from agent subdirectory' do
      described_class.write(agent_id: 'agent-a', filename: 'notes.json', content: '{"key":"val"}')
      result = described_class.read(agent_id: 'agent-a', filename: 'notes.json')
      expect(result[:success]).to be true
      expect(result[:content]).to eq('{"key":"val"}')
    end

    it 'returns not_found for missing files' do
      result = described_class.read(agent_id: 'agent-x', filename: 'missing.txt')
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:not_found)
    end
  end

  describe '.list' do
    it 'lists all files across agents' do
      described_class.write(agent_id: 'a', filename: 'f1.txt', content: 'x')
      described_class.write(agent_id: 'b', filename: 'f2.txt', content: 'y')
      result = described_class.list
      expect(result[:success]).to be true
      expect(result[:files].size).to eq(2)
    end

    it 'lists files for a specific agent' do
      described_class.write(agent_id: 'a', filename: 'f1.txt', content: 'x')
      described_class.write(agent_id: 'b', filename: 'f2.txt', content: 'y')
      result = described_class.list(agent_id: 'a')
      expect(result[:files].size).to eq(1)
    end

    it 'returns empty list for non-existent directory' do
      result = described_class.list(agent_id: 'nonexistent')
      expect(result[:files]).to be_empty
    end
  end

  describe '.cleanup' do
    it 'removes files older than max_age' do
      described_class.write(agent_id: 'a', filename: 'old.txt', content: 'old')
      path = File.join(tmpdir, 'a', 'old.txt')
      FileUtils.touch(path, mtime: Time.now - 90_000)

      described_class.write(agent_id: 'a', filename: 'new.txt', content: 'new')

      result = described_class.cleanup(max_age: 86_400)
      expect(result[:removed]).to eq(1)
      expect(File.exist?(File.join(tmpdir, 'a', 'new.txt'))).to be true
    end
  end
end
