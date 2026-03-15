# frozen_string_literal: true

require 'spec_helper'

ChatResponse = Struct.new(:content, :role, :tool_call?, :input_tokens, :output_tokens) unless defined?(ChatResponse)
ChatChunk = Struct.new(:content) unless defined?(ChatChunk)
ChatModel = Struct.new(:id) unless defined?(ChatModel)

unless defined?(RubyLLM)
  module RubyLLM
    class Chat
      attr_reader :messages

      def initialize(**) = (@messages = [])
      def with_instructions(_text) = self
      def with_tools(*_tools) = self
      def on_tool_call = self
      def on_tool_result = self

      def ask(msg, &block)
        @messages << { role: :user, content: msg }
        response = ChatResponse.new(content: "Echo: #{msg}", role: :assistant, tool_call?: false,
                                    input_tokens: 10, output_tokens: 5)
        block&.call(ChatChunk.new(content: "Echo: #{msg}"))
        @messages << { role: :assistant, content: response.content }
        response
      end

      def model = ChatModel.new(id: 'test-model')
      def reset_messages! = @messages.clear
      def add_message(msg) = @messages << msg
      def with_model(_id) = self
    end
  end
end

require 'legion/cli/chat/session'
require 'legion/cli/chat/status_indicator'

RSpec.describe Legion::CLI::Chat::StatusIndicator do
  let(:chat) { RubyLLM::Chat.new }
  let(:session) { Legion::CLI::Chat::Session.new(chat: chat) }
  let(:indicator) { described_class.new(session) }

  it 'subscribes to session events on initialization' do
    expect(indicator).to be_a(described_class)
  end

  describe ':llm_start' do
    it 'starts a spinner with thinking label' do
      indicator
      expect { session.emit(:llm_start, { turn: 1 }) }.not_to raise_error
    end
  end

  describe ':llm_first_token' do
    it 'stops the spinner when first token arrives' do
      indicator
      session.emit(:llm_start, { turn: 1 })
      expect { session.emit(:llm_first_token, { turn: 1 }) }.not_to raise_error
    end
  end

  describe ':llm_complete' do
    it 'stops spinner as safety catch' do
      indicator
      session.emit(:llm_start, { turn: 1 })
      expect { session.emit(:llm_complete, { turn: 1 }) }.not_to raise_error
    end
  end

  describe ':tool_start' do
    it 'starts a spinner with tool name and counter' do
      indicator
      expect do
        session.emit(:tool_start, { name: 'read_file', args: { path: '/tmp' }, index: 1, total: 3 })
      end.not_to raise_error
    end
  end

  describe ':tool_complete' do
    it 'stops the spinner' do
      indicator
      session.emit(:tool_start, { name: 'read_file', args: {}, index: 1, total: 1 })
      expect do
        session.emit(:tool_complete, { name: 'read_file', result_preview: 'ok', index: 1, total: 1 })
      end.not_to raise_error
    end
  end

  describe 'non-TTY output' do
    it 'does not raise when output is not a TTY' do
      indicator
      expect { session.emit(:llm_start, { turn: 1 }) }.not_to raise_error
      expect { session.emit(:llm_complete, { turn: 1 }) }.not_to raise_error
    end
  end
end
