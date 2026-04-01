# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/session_recovery'

RSpec.describe Legion::CLI::Chat::SessionRecovery do
  describe '.classify' do
    it 'returns :none for empty messages' do
      expect(described_class.classify([])).to eq(:none)
    end

    it 'returns :none when last message is assistant with content' do
      messages = [
        { role: :user, content: 'hello' },
        { role: :assistant, content: 'hi there' }
      ]
      expect(described_class.classify(messages)).to eq(:none)
    end

    it 'returns :interrupted_prompt when last message is user' do
      messages = [
        { role: :assistant, content: 'hi' },
        { role: :user, content: 'do something' }
      ]
      expect(described_class.classify(messages)).to eq(:interrupted_prompt)
    end

    it 'returns :interrupted_turn when last message is tool_result' do
      messages = [
        { role: :user, content: 'read file' },
        { role: :assistant, content: 'reading...', tool_calls: [{ name: 'read_file' }] },
        { role: :tool_result, content: 'file contents here' }
      ]
      expect(described_class.classify(messages)).to eq(:interrupted_turn)
    end

    it 'filters thinking-only assistant messages' do
      messages = [
        { role: :user, content: 'hello' },
        { role: :assistant, content: nil, tool_calls: [] }
      ]
      expect(described_class.classify(messages)).to eq(:interrupted_prompt)
    end

    it 'filters whitespace-only assistant messages' do
      messages = [
        { role: :user, content: 'hello' },
        { role: :assistant, content: "\n\n" }
      ]
      expect(described_class.classify(messages)).to eq(:interrupted_prompt)
    end
  end

  describe '.recover' do
    it 'returns no recovery for clean sessions' do
      messages = [
        { role: :user, content: 'hello' },
        { role: :assistant, content: 'hi' }
      ]
      result = described_class.recover(messages)
      expect(result[:state]).to eq(:none)
      expect(result[:recovery_message]).to be_nil
    end

    it 'returns recovery message for interrupted_prompt' do
      messages = [
        { role: :assistant, content: 'hi' },
        { role: :user, content: 'do something' }
      ]
      result = described_class.recover(messages)
      expect(result[:state]).to eq(:interrupted_prompt)
      expect(result[:recovery_message]).to include('Continue from where you left off')
    end

    it 'returns recovery message with tool name for interrupted_turn' do
      messages = [
        { role: :user, content: 'read file' },
        { role: :assistant, content: 'ok', tool_calls: [{ name: 'read_file' }] },
        { role: :tool_result, content: 'data' }
      ]
      result = described_class.recover(messages)
      expect(result[:state]).to eq(:interrupted_turn)
      expect(result[:recovery_message]).to include('read_file')
    end

    it 'removes trailing tool_result for interrupted_turn' do
      messages = [
        { role: :user, content: 'hello' },
        { role: :assistant, content: 'ok', tool_calls: [{ name: 'write_file' }] },
        { role: :tool_result, content: 'done' }
      ]
      result = described_class.recover(messages)
      expect(result[:messages].last[:role].to_s).not_to eq('tool_result')
    end

    it 'handles string-keyed hashes' do
      messages = [
        { 'role' => 'user', 'content' => 'hello' },
        { 'role' => 'assistant', 'content' => 'hi' }
      ]
      result = described_class.recover(messages)
      expect(result[:state]).to eq(:none)
    end
  end
end
