# frozen_string_literal: true

require 'spec_helper'
require 'open3'

require 'legion/cli/review_command'

ReviewResponse = Struct.new(:content)

RSpec.describe Legion::CLI::Review do
  let(:review_response) do
    <<~REVIEW
      [CRITICAL] auth.rb:15 - SQL injection vulnerability in user lookup
      [WARNING] auth.rb:23 - Missing nil check on session token
      [SUGGESTION] auth.rb:30 - Extract magic number into a constant
      [NOTE] auth.rb:1 - Consider adding module documentation
      SUMMARY: Auth module has a critical SQL injection vulnerability that must be fixed.
    REVIEW
  end

  let(:fake_chat) do
    chat = double('chat')
    allow(chat).to receive(:ask).and_return(ReviewResponse.new(content: review_response))
    chat
  end

  before do
    allow(Legion::CLI::Connection).to receive(:config_dir=)
    allow(Legion::CLI::Connection).to receive(:log_level=)
    allow(Legion::CLI::Connection).to receive(:ensure_llm)
    allow(Legion::CLI::Connection).to receive(:shutdown)
    allow(Legion::LLM).to receive(:chat).and_return(fake_chat)
  end

  describe 'fetch_staged_diff' do
    it 'returns staged diff and stat' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', '--staged')
        .and_return(["diff --git a/foo\n", '', double(success?: true)])
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', '--staged', '--stat')
        .and_return([' foo.rb | 2 +-', '', double(success?: true)])

      diff, context = instance.fetch_staged_diff
      expect(diff).to include('diff --git')
      expect(context[:mode]).to eq('staged')
    end
  end

  describe 'fetch_working_diff' do
    it 'returns working directory diff' do
      instance = described_class.new
      allow(Open3).to receive(:capture3)
        .with('git', 'diff')
        .and_return(["diff --git a/bar\n", '', double(success?: true)])
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', '--stat')
        .and_return([' bar.rb | 1 +', '', double(success?: true)])

      diff, context = instance.fetch_working_diff
      expect(diff).to include('diff --git')
      expect(context[:mode]).to eq('working')
    end
  end

  describe 'fetch_branch_diff' do
    it 'returns branch diff with log' do
      instance = described_class.new([], { base: 'main' })
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', 'main...HEAD')
        .and_return(["diff content\n", '', double(success?: true)])
      allow(Open3).to receive(:capture3)
        .with('git', 'diff', 'main...HEAD', '--stat')
        .and_return(['stat content', '', double(success?: true)])
      allow(Open3).to receive(:capture3)
        .with('git', 'log', 'main..HEAD', '--oneline', '--no-decorate')
        .and_return(['abc add feature', '', double(success?: true)])

      diff, context = instance.fetch_branch_diff
      expect(diff).to include('diff content')
      expect(context[:mode]).to eq('branch')
      expect(context[:log]).to include('add feature')
    end
  end

  describe 'parse_review' do
    it 'parses findings by severity' do
      instance = described_class.new
      result = instance.parse_review(review_response, { mode: 'working' })

      expect(result[:findings].length).to eq(4)
      expect(result[:findings][0][:severity]).to eq('critical')
      expect(result[:findings][1][:severity]).to eq('warning')
      expect(result[:findings][2][:severity]).to eq('suggestion')
      expect(result[:findings][3][:severity]).to eq('note')
    end

    it 'extracts summary' do
      instance = described_class.new
      result = instance.parse_review(review_response, { mode: 'working' })
      expect(result[:summary]).to include('SQL injection')
    end

    it 'handles response with no findings' do
      instance = described_class.new
      result = instance.parse_review("SUMMARY: No issues found.\n", { mode: 'staged' })
      expect(result[:findings]).to be_empty
      expect(result[:summary]).to eq('No issues found.')
    end

    it 'parses fix blocks' do
      fix_response = <<~REVIEW
        [CRITICAL] foo.rb:10 - Bug found
        SUMMARY: Has a bug.
        FIX foo.rb:10
        ```diff
        -old line
        +new line
        ```
      REVIEW
      instance = described_class.new
      result = instance.parse_review(fix_response, { mode: 'working' })
      expect(result[:fixes].length).to eq(1)
      expect(result[:fixes][0][:patch]).to include('-old line')
    end
  end

  describe 'build_review_prompt' do
    it 'includes diff and context' do
      instance = described_class.new([], { fix: false })
      prompt = instance.build_review_prompt('diff content', { mode: 'staged', stat: 'stat' })
      expect(prompt).to include('diff content')
      expect(prompt).to include('CRITICAL')
      expect(prompt).to include('WARNING')
      expect(prompt).to include('SUGGESTION')
    end

    it 'includes fix instructions when --fix is set' do
      instance = described_class.new([], { fix: true })
      prompt = instance.build_review_prompt('diff', { mode: 'working', stat: 'stat' })
      expect(prompt).to include('FIX file:line')
      expect(prompt).to include('unified diff')
    end

    it 'includes PR context for PR mode' do
      instance = described_class.new([], { fix: false })
      context = { mode: 'pr', pr: 42, title: 'Add auth', body: 'Adds authentication', stat: 'files' }
      prompt = instance.build_review_prompt('diff', context)
      expect(prompt).to include('PR #42')
      expect(prompt).to include('Add auth')
    end
  end

  describe 'run_review' do
    it 'returns parsed review from LLM' do
      instance = described_class.new([], { model: nil, provider: nil, fix: false })
      result = instance.run_review('diff text', { mode: 'working', stat: 'stat' })
      expect(result[:findings].length).to eq(4)
      expect(result[:summary]).to include('SQL injection')
    end
  end

  describe 'build_context_section' do
    it 'formats PR context' do
      instance = described_class.new
      section = instance.build_context_section(
        mode: 'pr', pr: 5, title: 'Fix bug', body: 'Fixes #123', stat: 'foo.rb +1/-1'
      )
      expect(section).to include('PR #5')
      expect(section).to include('Fix bug')
    end

    it 'formats branch context' do
      instance = described_class.new
      section = instance.build_context_section(
        mode: 'branch', base: 'main', stat: 'stat', log: 'abc commit'
      )
      expect(section).to include('main')
      expect(section).to include('abc commit')
    end

    it 'formats working/staged context' do
      instance = described_class.new
      section = instance.build_context_section(mode: 'staged', stat: 'stat')
      expect(section).to include('Staged')
    end
  end
end
