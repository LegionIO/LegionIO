# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/cli/chat/memory_store'

RSpec.describe Legion::CLI::Chat::MemoryStore do
  let(:tmpdir) { Dir.mktmpdir('memory-test') }
  let(:project_dir) { File.join(tmpdir, 'project') }

  before do
    FileUtils.mkdir_p(project_dir)
    stub_const('Legion::CLI::Chat::MemoryStore::DEFAULT_GLOBAL_DIR', File.join(tmpdir, 'global'))
    stub_const('Legion::CLI::Chat::MemoryStore::DEFAULT_GLOBAL_FILE', File.join(tmpdir, 'global', 'global.md'))
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.add' do
    it 'creates a project memory file with an entry' do
      path = described_class.add('Ruby 3.4 is required', base_dir: project_dir)

      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include('Ruby 3.4 is required')
      expect(content).to include('# Project Memory')
    end

    it 'appends to an existing memory file' do
      described_class.add('first entry', base_dir: project_dir)
      described_class.add('second entry', base_dir: project_dir)

      entries = described_class.list(base_dir: project_dir)
      expect(entries.length).to eq(2)
      expect(entries.first).to include('first entry')
      expect(entries.last).to include('second entry')
    end

    it 'writes to global memory when scope is :global' do
      path = described_class.add('global fact', scope: :global)

      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include('global fact')
      expect(content).to include('# Global Memory')
    end
  end

  describe '.list' do
    it 'returns empty array when no memory file exists' do
      expect(described_class.list(base_dir: project_dir)).to eq([])
    end

    it 'returns memory entries as strings' do
      described_class.add('entry one', base_dir: project_dir)
      described_class.add('entry two', base_dir: project_dir)

      entries = described_class.list(base_dir: project_dir)
      expect(entries.length).to eq(2)
      expect(entries.first).to include('entry one')
    end
  end

  describe '.forget' do
    it 'removes matching entries' do
      described_class.add('keep this', base_dir: project_dir)
      described_class.add('delete this', base_dir: project_dir)

      removed = described_class.forget('delete', base_dir: project_dir)
      expect(removed).to eq(1)

      entries = described_class.list(base_dir: project_dir)
      expect(entries.length).to eq(1)
      expect(entries.first).to include('keep this')
    end

    it 'returns 0 when no entries match' do
      described_class.add('entry', base_dir: project_dir)
      expect(described_class.forget('nomatch', base_dir: project_dir)).to eq(0)
    end

    it 'returns 0 when no memory file exists' do
      expect(described_class.forget('anything', base_dir: project_dir)).to eq(0)
    end
  end

  describe '.clear' do
    it 'deletes the memory file' do
      described_class.add('entry', base_dir: project_dir)
      expect(described_class.clear(base_dir: project_dir)).to be true
      expect(described_class.list(base_dir: project_dir)).to eq([])
    end

    it 'returns false when no memory file exists' do
      expect(described_class.clear(base_dir: project_dir)).to be false
    end
  end

  describe '.search' do
    it 'finds matching entries across scopes' do
      described_class.add('ruby version is 3.4', base_dir: project_dir)
      described_class.add('python version is 3.12', base_dir: project_dir)

      results = described_class.search('ruby', base_dir: project_dir)
      expect(results.length).to eq(1)
      expect(results.first[:text]).to include('ruby version is 3.4')
    end

    it 'is case-insensitive' do
      described_class.add('Ruby is great', base_dir: project_dir)

      results = described_class.search('ruby', base_dir: project_dir)
      expect(results.length).to eq(1)
    end

    it 'returns empty array when nothing matches' do
      described_class.add('entry', base_dir: project_dir)
      expect(described_class.search('nomatch', base_dir: project_dir)).to eq([])
    end
  end

  describe '.load_context' do
    it 'returns nil when no memory files exist' do
      expect(described_class.load_context(project_dir)).to be_nil
    end

    it 'returns formatted context when memory exists' do
      described_class.add('important fact', base_dir: project_dir)

      context = described_class.load_context(project_dir)
      expect(context).to include('Project Memory')
      expect(context).to include('important fact')
    end
  end

  describe '.load_all' do
    it 'returns empty array when no memory files exist' do
      expect(described_class.load_all(project_dir)).to eq([])
    end

    it 'returns project and global memories when both exist' do
      described_class.add('project fact', scope: :project, base_dir: project_dir)
      described_class.add('global fact', scope: :global)

      memories = described_class.load_all(project_dir)
      expect(memories.length).to eq(2)
    end
  end
end
