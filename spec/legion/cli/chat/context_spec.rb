# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/context'

RSpec.describe Legion::CLI::Chat::Context do
  let(:project_root) { File.expand_path('../../../..', __dir__) }
  let(:tmpdir) { Dir.mktmpdir('context-test') }

  after { FileUtils.rm_rf(tmpdir) }

  describe '.detect' do
    it 'returns a hash with project info' do
      ctx = described_class.detect(project_root)
      expect(ctx).to be_a(Hash)
      expect(ctx).to have_key(:project_type)
      expect(ctx).to have_key(:directory)
    end

    it 'detects ruby projects' do
      ctx = described_class.detect(project_root)
      expect(ctx[:project_type]).to eq(:ruby)
    end

    it 'detects javascript project' do
      File.write(File.join(tmpdir, 'package.json'), '{}')
      expect(described_class.detect(tmpdir)[:project_type]).to eq(:javascript)
    end

    it 'detects terraform project' do
      File.write(File.join(tmpdir, 'main.tf'), '')
      expect(described_class.detect(tmpdir)[:project_type]).to eq(:terraform)
    end

    it 'detects python project' do
      File.write(File.join(tmpdir, 'pyproject.toml'), '')
      expect(described_class.detect(tmpdir)[:project_type]).to eq(:python)
    end

    it 'returns nil for unknown project type' do
      expect(described_class.detect(tmpdir)[:project_type]).to be_nil
    end

    it 'detects git branch from HEAD' do
      git_dir = File.join(tmpdir, '.git')
      FileUtils.mkdir_p(git_dir)
      File.write(File.join(git_dir, 'HEAD'), "ref: refs/heads/feature/test\n")
      expect(described_class.detect(tmpdir)[:git_branch]).to eq('feature/test')
    end

    it 'handles detached HEAD' do
      git_dir = File.join(tmpdir, '.git')
      FileUtils.mkdir_p(git_dir)
      File.write(File.join(git_dir, 'HEAD'), "abc12345678deadbeef\n")
      expect(described_class.detect(tmpdir)[:git_branch]).to eq('abc12345')
    end

    it 'returns nil git_branch when not a git repo' do
      expect(described_class.detect(tmpdir)[:git_branch]).to be_nil
    end
  end

  describe '.detect_project_file' do
    it 'returns path to first matching project marker' do
      File.write(File.join(tmpdir, 'Gemfile'), '')
      expect(described_class.detect_project_file(tmpdir)).to eq(File.join(tmpdir, 'Gemfile'))
    end

    it 'returns nil when no markers found' do
      expect(described_class.detect_project_file(tmpdir)).to be_nil
    end
  end

  describe '.to_system_prompt' do
    it 'returns a string' do
      result = described_class.to_system_prompt(project_root)
      expect(result).to be_a(String)
      expect(result).to include('Legion')
    end

    it 'includes working directory' do
      result = described_class.to_system_prompt(project_root)
      expect(result).to include(project_root)
    end

    it 'includes project type when detected' do
      File.write(File.join(tmpdir, 'Gemfile'), '')
      result = described_class.to_system_prompt(tmpdir)
      expect(result).to include('Project type: ruby')
    end

    it 'includes CLAUDE.md content when present' do
      File.write(File.join(tmpdir, 'CLAUDE.md'), '# Test Project Rules')
      result = described_class.to_system_prompt(tmpdir)
      expect(result).to include('Project Instructions')
      expect(result).to include('Test Project Rules')
    end

    it 'includes extra directories' do
      extra = Dir.mktmpdir('extra')
      result = described_class.to_system_prompt(tmpdir, extra_dirs: [extra])
      expect(result).to include("Additional directory: #{File.expand_path(extra)}")
      FileUtils.rm_rf(extra)
    end

    it 'skips non-existent extra directories' do
      result = described_class.to_system_prompt(tmpdir, extra_dirs: ['/nonexistent/path'])
      expect(result).not_to include('Additional directory')
    end
  end

  describe '.cognitive_awareness' do
    it 'returns nil when no cognitive context is available' do
      allow(described_class).to receive(:memory_hint).and_return(nil)
      allow(described_class).to receive(:apollo_hint).and_return(nil)
      expect(described_class.cognitive_awareness(tmpdir)).to be_nil
    end

    it 'includes memory hint when entries exist' do
      allow(described_class).to receive(:memory_hint).and_return('  Memory: 3 project + 2 global entries')
      allow(described_class).to receive(:apollo_hint).and_return(nil)
      result = described_class.cognitive_awareness(tmpdir)
      expect(result).to include('Memory: 3 project + 2 global')
    end

    it 'includes apollo hint when available' do
      allow(described_class).to receive(:memory_hint).and_return(nil)
      allow(described_class).to receive(:apollo_hint).and_return('  Apollo knowledge graph: online')
      result = described_class.cognitive_awareness(tmpdir)
      expect(result).to include('Apollo knowledge graph: online')
    end
  end

  describe '.memory_hint' do
    it 'returns hint with entry counts' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list)
        .with(base_dir: tmpdir).and_return(%w[entry1 entry2])
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list)
        .with(scope: :global).and_return(%w[global1])
      result = described_class.memory_hint(tmpdir)
      expect(result).to include('2 project')
      expect(result).to include('1 global')
    end

    it 'returns nil when no entries exist' do
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list)
        .with(base_dir: tmpdir).and_return([])
      allow(Legion::CLI::Chat::MemoryStore).to receive(:list)
        .with(scope: :global).and_return([])
      expect(described_class.memory_hint(tmpdir)).to be_nil
    end
  end

  describe '.apollo_hint' do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
    end

    it 'returns online hint when apollo is available' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { available: true } })
      )
      allow(mock_http).to receive(:get).and_return(response)
      result = described_class.apollo_hint
      expect(result).to include('Apollo knowledge graph: online')
    end

    it 'returns nil when apollo is not available' do
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(
        JSON.generate({ data: { available: false } })
      )
      allow(mock_http).to receive(:get).and_return(response)
      expect(described_class.apollo_hint).to be_nil
    end

    it 'returns nil on connection refused' do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
      expect(described_class.apollo_hint).to be_nil
    end
  end
end
