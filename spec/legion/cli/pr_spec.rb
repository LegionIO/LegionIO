# frozen_string_literal: true

require 'spec_helper'
require 'open3'

require 'legion/cli/pr_command'

PrResponse = Struct.new(:content)

RSpec.describe Legion::CLI::Pr do
  let(:fake_chat) do
    chat = double('chat')
    allow(chat).to receive(:ask).and_return(
      PrResponse.new(content: "Add user authentication\n\n## Summary\n- Add JWT auth\n- Add login endpoint")
    )
    chat
  end

  before do
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_llm)
    allow(Legion::CLI::Connection).to receive(:shutdown)
    allow(Legion::LLM).to receive(:chat).and_return(fake_chat)
  end

  describe 'current_branch' do
    it 'returns the current git branch' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'rev-parse', '--abbrev-ref', 'HEAD')
        .and_return(["feature/auth\n", '', double(success?: true)])

      expect(instance.current_branch).to eq('feature/auth')
    end
  end

  describe 'branch_diff' do
    it 'returns diff against base branch' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', 'main...HEAD')
        .and_return(["diff --git a/auth.rb\n+login code\n", '', double(success?: true)])

      result = instance.branch_diff('main')
      expect(result).to include('diff --git')
    end
  end

  describe 'branch_log' do
    it 'returns commit log since base' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'log', 'main..HEAD', '--oneline', '--no-decorate')
        .and_return(["abc123 add auth\ndef456 add tests\n", '', double(success?: true)])

      result = instance.branch_log('main')
      expect(result).to include('add auth')
    end
  end

  describe 'detect_remote' do
    it 'parses HTTPS remote URL' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'remote', 'get-url', 'origin')
        .and_return(["https://github.com/LegionIO/LegionIO.git\n", '', double(success?: true)])

      owner, repo = instance.detect_remote
      expect(owner).to eq('LegionIO')
      expect(repo).to eq('LegionIO')
    end

    it 'parses SSH remote URL' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'remote', 'get-url', 'origin')
        .and_return(["git@github.com:LegionIO/LegionIO.git\n", '', double(success?: true)])

      owner, repo = instance.detect_remote
      expect(owner).to eq('LegionIO')
      expect(repo).to eq('LegionIO')
    end

    it 'handles URLs without .git suffix' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'remote', 'get-url', 'origin')
        .and_return(["https://github.com/org/repo\n", '', double(success?: true)])

      owner, repo = instance.detect_remote
      expect(owner).to eq('org')
      expect(repo).to eq('repo')
    end
  end

  describe 'resolve_token' do
    it 'uses --token option when provided' do
      instance = described_class.new([], { token: 'my-token' })
      expect(instance.resolve_token).to eq('my-token')
    end

    it 'falls back to GITHUB_TOKEN env var' do
      instance = described_class.new
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return('env-token')
      expect(instance.resolve_token).to eq('env-token')
    end

    it 'raises when no token available' do
      instance = described_class.new
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('GH_TOKEN', nil).and_return(nil)
      expect { instance.resolve_token }.to raise_error(Legion::CLI::Error, /No GitHub token/)
    end
  end

  describe 'build_prompt' do
    it 'includes diff, stat, log, and branch in prompt' do
      instance = described_class.new
      prompt = instance.build_prompt('diff', 'stat', 'log', 'feature/auth')
      expect(prompt).to include('diff')
      expect(prompt).to include('stat')
      expect(prompt).to include('log')
      expect(prompt).to include('feature/auth')
      expect(prompt).to include('under 70 characters')
    end
  end

  describe 'parse_pr_response' do
    it 'splits title and body from LLM response' do
      instance = described_class.new
      title, body = instance.parse_pr_response("My Title\n\n## Summary\n- thing one\n- thing two")
      expect(title).to eq('My Title')
      expect(body).to include('## Summary')
    end

    it 'handles single-line response' do
      instance = described_class.new
      title, body = instance.parse_pr_response('Just a title')
      expect(title).to eq('Just a title')
      expect(body).to eq('')
    end
  end

  describe 'generate_pr_content' do
    it 'returns title and body from LLM' do
      instance = described_class.new([], { model: nil, provider: nil })
      title, body = instance.generate_pr_content('diff', 'stat', 'log', 'feature/auth')
      expect(title).to eq('Add user authentication')
      expect(body).to include('## Summary')
    end
  end

  describe 'push_branch' do
    it 'pushes to origin' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'push', '-u', 'origin', 'feature/auth')
        .and_return(['', '', double(success?: true)])

      expect { instance.push_branch('feature/auth') }.not_to raise_error
    end

    it 'raises on push failure' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'push', '-u', 'origin', 'feature/auth')
        .and_return(['', 'rejected', double(success?: false)])

      expect { instance.push_branch('feature/auth') }.to raise_error(
        Legion::CLI::Error, /git push failed/
      )
    end
  end
end
