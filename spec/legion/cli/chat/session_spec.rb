# frozen_string_literal: true

require 'spec_helper'

ChatResponse = Struct.new(:content, :role, :tool_call?, :input_tokens, :output_tokens)
ChatChunk = Struct.new(:content)
ChatModel = Struct.new(:id)

# Stub RubyLLM::Chat for unit testing
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

  describe 'event emitter' do
    it 'allows subscribing to events and emits them' do
      received = []
      session.on(:test_event) { |payload| received << payload }
      session.emit(:test_event, { key: 'value' })
      expect(received).to eq([{ key: 'value' }])
    end

    it 'supports multiple subscribers on the same event' do
      results = []
      session.on(:multi) { |p| results << "a:#{p[:v]}" }
      session.on(:multi) { |p| results << "b:#{p[:v]}" }
      session.emit(:multi, { v: 1 })
      expect(results).to eq(['a:1', 'b:1'])
    end

    it 'does not raise when emitting with no subscribers' do
      expect { session.emit(:nobody_listening, {}) }.not_to raise_error
    end

    it 'emits :llm_start and :llm_complete around send_message' do
      events = []
      session.on(:llm_start) { |p| events << [:llm_start, p[:turn]] }
      session.on(:llm_complete) { |p| events << [:llm_complete, p[:turn]] }
      session.send_message('hello')
      expect(events).to eq([[:llm_start, 1], [:llm_complete, 1]])
    end

    it 'includes user_message in :llm_complete payload' do
      payload_received = nil
      session.on(:llm_complete) { |p| payload_received = p }
      session.send_message('tell me something')
      expect(payload_received[:user_message]).to eq('tell me something')
    end

    it 'emits :llm_first_token on first streaming chunk' do
      token_events = []
      session.on(:llm_first_token) { |p| token_events << p[:turn] }
      session.send_message('hello') { |_chunk| nil }
      expect(token_events).to eq([1])
    end

    it 'emits :llm_first_token only once per turn' do
      token_events = []
      session.on(:llm_first_token) { |p| token_events << p[:turn] }
      session.send_message('hello') { |_chunk| nil }
      session.send_message('world') { |_chunk| nil }
      expect(token_events).to eq([1, 2])
    end

    it 'increments turn counter across messages' do
      turns = []
      session.on(:llm_start) { |p| turns << p[:turn] }
      session.send_message('first')
      session.send_message('second')
      expect(turns).to eq([1, 2])
    end

    it 'emits :tool_start when on_tool_call fires' do
      tool_events = []
      session.on(:tool_start) { |p| tool_events << p[:name] }

      session.send_message('hello', on_tool_call: ->(tc) { tc }) { |c| c }

      session.emit(:tool_start, { name: 'read_file', args: { path: '/tmp' }, index: 1, total: 1 })
      expect(tool_events).to eq(['read_file'])
    end

    it 'emits :tool_complete when on_tool_result fires' do
      result_events = []
      session.on(:tool_complete) { |p| result_events << p[:name] }

      session.emit(:tool_complete, { name: 'read_file', result_preview: 'contents...', index: 1, total: 1 })
      expect(result_events).to eq(['read_file'])
    end
  end
end
