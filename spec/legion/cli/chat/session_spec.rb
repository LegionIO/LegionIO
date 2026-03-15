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
    def add_message(msg) = @messages << msg
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

  describe '#estimated_cost' do
    it 'returns zero with no usage' do
      expect(session.estimated_cost).to eq(0)
    end

    it 'calculates cost from token usage' do
      session.send_message('hello') # 10 input, 5 output per stub
      cost = session.estimated_cost
      expected = (10 * described_class::INPUT_RATE) + (5 * described_class::OUTPUT_RATE)
      expect(cost).to eq(expected)
    end

    it 'accumulates across multiple messages' do
      session.send_message('hello')
      session.send_message('world')
      cost = session.estimated_cost
      expected = (20 * described_class::INPUT_RATE) + (10 * described_class::OUTPUT_RATE)
      expect(cost).to eq(expected)
    end
  end

  describe 'budget enforcement' do
    it 'allows messages when under budget' do
      budget_session = described_class.new(chat: RubyLLM::Chat.new, budget_usd: 10.0)
      expect { budget_session.send_message('hello') }.not_to raise_error
    end

    it 'raises BudgetExceeded when cost reaches limit' do
      # Each message: 10 input + 5 output tokens
      # Cost per msg: 10 * 0.000003 + 5 * 0.000015 = ~0.000105
      budget_session = described_class.new(chat: RubyLLM::Chat.new, budget_usd: 0.0001)
      budget_session.send_message('first') # costs ~0.000105, exceeds 0.0001
      expect { budget_session.send_message('second') }.to raise_error(
        described_class::BudgetExceeded, /Budget exceeded/
      )
    end

    it 'does not check budget when budget_usd is nil' do
      no_budget = described_class.new(chat: RubyLLM::Chat.new)
      5.times { no_budget.send_message('hello') }
      # Should never raise
    end

    it 'includes cost details in error message' do
      budget_session = described_class.new(chat: RubyLLM::Chat.new, budget_usd: 0.0001)
      budget_session.send_message('first')
      expect { budget_session.send_message('second') }.to raise_error(
        described_class::BudgetExceeded, /\$.*spent of \$.*limit/
      )
    end
  end
end
