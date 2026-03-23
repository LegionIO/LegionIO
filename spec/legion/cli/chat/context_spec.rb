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
end
