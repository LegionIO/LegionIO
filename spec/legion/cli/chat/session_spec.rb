# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'

# Stub RubyLLM::Chat for unit testing
module RubyLLM
  class Chat
    attr_reader :messages

    def initialize(**) = (@messages = [])
    def with_instructions(text) = (self)
    def with_tools(*tools) = (self)
    def on_tool_call(&block) = (self)
    def on_tool_result(&block) = (self)
    def ask(msg, &block)
      @messages << { role: :user, content: msg }
      response = OpenStruct.new(content: "Echo: #{msg}", role: :assistant, tool_call?: false,
                                input_tokens: 10, output_tokens: 5)
      block&.call(OpenStruct.new(content: "Echo: #{msg}"))
      @messages << { role: :assistant, content: response.content }
      response
    end
    def model = OpenStruct.new(id: 'test-model')
    def reset_messages! = @messages.clear
    def with_model(id) = (self)
  end
end

require 'legion/cli/chat/session'

RSpec.describe Legion::CLI::Chat::Session do
  subject(:session) { described_class.new(chat: RubyLLM::Chat.new) }

  it 'initializes with a chat object' do
    expect(session).to be_a(described_class)
  end

  it 'sends a message and returns a response' do
    response = session.send_message('hello')
    expect(response.content).to eq('Echo: hello')
  end

  it 'tracks message counts' do
    session.send_message('hello')
    expect(session.stats[:messages_sent]).to eq(1)
    expect(session.stats[:messages_received]).to eq(1)
  end

  it 'reports model_id' do
    expect(session.model_id).to eq('test-model')
  end

  it 'tracks elapsed time' do
    expect(session.elapsed).to be_a(Float)
    expect(session.elapsed).to be >= 0
  end
end
