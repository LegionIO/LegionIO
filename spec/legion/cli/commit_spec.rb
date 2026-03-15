# frozen_string_literal: true

require 'spec_helper'
require 'open3'

CommitResponse = Struct.new(:content)

# Stub LLM for commit message generation
module Legion
  module LLM
    def self.chat(**_opts)
      FakeChat.new
    end

    class FakeChat
      def ask(_prompt)
        CommitResponse.new(content: "add new feature\n\n- update config\n- fix tests")
      end
    end
  end
end

require 'legion/cli/commit_command'

RSpec.describe Legion::CLI::Commit do
  let(:out) { Legion::CLI::Output::Formatter.new(json: false, color: false) }

  before do
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_llm)
    allow(Legion::CLI::Connection).to receive(:shutdown)
  end

  describe 'staged_diff' do
    it 'calls git diff --staged' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', '--staged')
        .and_return(["diff --git a/foo\n+bar\n", '', double(success?: true)])

      result = instance.staged_diff
      expect(result).to include('diff --git')
    end
  end

  describe 'staged_stat' do
    it 'calls git diff --staged --stat' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', '--staged', '--stat')
        .and_return([" foo.rb | 2 +-\n 1 file changed\n", '', double(success?: true)])

      result = instance.staged_stat
      expect(result).to include('foo.rb')
    end
  end

  describe 'recent_commits' do
    it 'returns recent git log' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'log', '--oneline', '-10', '--no-decorate')
        .and_return(["abc1234 add something\ndef5678 fix bug\n", '', double(success?: true)])

      result = instance.recent_commits
      expect(result).to include('add something')
    end
  end

  describe 'build_prompt' do
    it 'includes diff, stat, and log in prompt' do
      instance = described_class.new
      prompt = instance.build_prompt('diff content', 'stat content', 'log content')
      expect(prompt).to include('diff content')
      expect(prompt).to include('stat content')
      expect(prompt).to include('log content')
      expect(prompt).to include('imperative mood')
    end

    it 'truncates long diffs' do
      instance = described_class.new
      long_diff = 'x' * 10_000
      prompt = instance.build_prompt(long_diff, 'stat', 'log')
      expect(prompt.length).to be < 10_000
    end
  end

  describe 'generate_message' do
    it 'returns LLM-generated commit message' do
      instance = described_class.new([], { model: nil, provider: nil })
      message = instance.generate_message('diff', 'stat', 'log')
      expect(message).to include('add new feature')
    end
  end

  describe 'run_commit' do
    it 'runs git commit with message' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'commit', '-m', 'test message')
        .and_return(['', '', double(success?: true)])

      expect { instance.run_commit('test message') }.not_to raise_error
    end

    it 'raises on git commit failure' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'commit', '-m', 'test message')
        .and_return(['', 'error: nothing to commit', double(success?: false)])

      expect { instance.run_commit('test message') }.to raise_error(
        Legion::CLI::Error, /git commit failed/
      )
    end

    it 'passes --amend flag when requested' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'commit', '--amend', '-m', 'amended message')
        .and_return(['', '', double(success?: true)])

      expect { instance.run_commit('amended message', amend: true) }.not_to raise_error
    end
  end

  describe 'stage_all' do
    it 'runs git add -u' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'add', '-u')
        .and_return(['', '', double(success?: true)])

      expect { instance.stage_all }.not_to raise_error
    end

    it 'raises on failure' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'add', '-u')
        .and_return(['', 'fatal: not a git repository', double(success?: false)])

      expect { instance.stage_all }.to raise_error(Legion::CLI::Error, /git add -u failed/)
    end
  end
end
