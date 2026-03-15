# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/agent_delegator'

RSpec.describe Legion::CLI::Chat::AgentDelegator do
  describe '.delegate?' do
    it 'detects @mention pattern' do
      expect(described_class.delegate?('@reviewer check this')).to eq(:at_mention)
    end

    it 'detects /agent pattern' do
      expect(described_class.delegate?('/agent reviewer check this')).to eq(:slash)
    end

    it 'returns false for regular input' do
      expect(described_class.delegate?('regular message')).to be false
    end

    it 'returns false for email-like @' do
      expect(described_class.delegate?('email@domain.com')).to be false
    end
  end

  describe '.parse' do
    it 'parses @mention into agent_name and task' do
      result = described_class.parse('@reviewer check this file for bugs')
      expect(result[:agent_name]).to eq('reviewer')
      expect(result[:task]).to eq('check this file for bugs')
    end

    it 'parses /agent command' do
      result = described_class.parse('/agent debugger find the memory leak')
      expect(result[:agent_name]).to eq('debugger')
      expect(result[:task]).to eq('find the memory leak')
    end

    it 'returns nil for non-delegation input' do
      expect(described_class.parse('regular message')).to be_nil
    end
  end

  describe '.build_agent_prompt' do
    it 'combines system prompt and task' do
      agent = { system_prompt: 'You are a reviewer.', name: 'reviewer' }
      prompt = described_class.build_agent_prompt(agent, 'review main.rb')
      expect(prompt).to include('You are a reviewer.')
      expect(prompt).to include('review main.rb')
    end

    it 'handles missing system prompt' do
      agent = { system_prompt: nil, name: 'minimal' }
      prompt = described_class.build_agent_prompt(agent, 'do something')
      expect(prompt).to include('do something')
    end
  end
end
