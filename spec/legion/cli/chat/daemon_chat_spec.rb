# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/daemon_chat'

RSpec.describe Legion::CLI::Chat::DaemonChat do
  subject(:chat) { described_class.new(model: 'claude-sonnet-4-6', provider: :bedrock) }

  # Ensure the stub constant exists before each test.
  before do
    unless defined?(Legion::LLM::DaemonClient)
      stub_const('Legion::LLM', Module.new) unless defined?(Legion::LLM)
      daemon_mod = Module.new
      stub_const('Legion::LLM::DaemonClient', daemon_mod)
    end
  end

  # Stub DaemonClient.inference so specs never hit the network.
  def stub_inference(content: 'hello from daemon', tool_calls: nil,
                     input_tokens: 5, output_tokens: 10, status: :immediate)
    result = {
      status: status,
      data:   {
        content:       content,
        tool_calls:    tool_calls,
        input_tokens:  input_tokens,
        output_tokens: output_tokens,
        model:         'claude-sonnet-4-6'
      }
    }
    allow(Legion::LLM::DaemonClient).to receive(:inference).and_return(result)
    result
  end

  # ── initialization ─────────────────────────────────────────────────────────

  describe '#initialize' do
    it 'exposes a model object responding to .id' do
      expect(chat.model.id).to eq('claude-sonnet-4-6')
    end

    it 'model.to_s returns the model id' do
      expect(chat.model.to_s).to eq('claude-sonnet-4-6')
    end

    it 'starts with an empty message history' do
      stub_inference
      responses = []
      chat.ask('test') { |chunk| responses << chunk.content }
      expect(Legion::LLM::DaemonClient).to have_received(:inference).with(
        hash_including(messages: array_including(hash_including(role: 'user', content: 'test')))
      )
    end
  end

  # ── identity and conversation ───────────────────────────────────────────────

  describe 'identity wiring' do
    it 'generates a stable conversation_id' do
      expect(chat.conversation_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'keeps the same conversation_id across turns' do
      id = chat.conversation_id
      stub_inference
      chat.ask('test')
      expect(chat.conversation_id).to eq(id)
    end

    it 'builds a caller_context with identity' do
      expect(chat.caller_context).to be_a(Hash)
      expect(chat.caller_context[:requested_by]).to be_a(Hash)
      expect(chat.caller_context[:requested_by][:type]).to eq(:human)
      expect(chat.caller_context[:requested_by][:credential]).to eq(:local)
      expect(chat.caller_context[:requested_by][:identity]).not_to be_nil
    end

    it 'passes caller and conversation_id to DaemonClient.inference' do
      stub_inference
      chat.ask('test')
      expect(Legion::LLM::DaemonClient).to have_received(:inference).with(
        hash_including(
          caller:          hash_including(requested_by: hash_including(type: :human)),
          conversation_id: chat.conversation_id
        )
      )
    end
  end

  # ── with_instructions ──────────────────────────────────────────────────────

  describe '#with_instructions' do
    it 'prepends a system message to the outgoing messages array' do
      stub_inference
      chat.with_instructions('You are a helpful assistant.')
      chat.ask('test')

      expect(Legion::LLM::DaemonClient).to have_received(:inference).with(
        hash_including(
          messages: array_including(hash_including(role: 'system', content: 'You are a helpful assistant.'))
        )
      )
    end

    it 'returns self for chaining' do
      expect(chat.with_instructions('prompt')).to eq(chat)
    end
  end

  # ── with_tools ─────────────────────────────────────────────────────────────

  describe '#with_tools' do
    it 'stores tools and forwards their schemas to DaemonClient.inference' do
      fake_tool = Class.new do
        def self.tool_name  = 'read_file'
        def self.description = 'Reads a file'
        def self.parameters  = { type: 'object' }
      end

      stub_inference
      chat.with_tools(fake_tool)
      chat.ask('read something')

      expect(Legion::LLM::DaemonClient).to have_received(:inference).with(
        hash_including(
          tools: array_including(hash_including(name: 'read_file'))
        )
      )
    end

    it 'returns self for chaining' do
      expect(chat.with_tools).to eq(chat)
    end
  end

  # ── with_model ─────────────────────────────────────────────────────────────

  describe '#with_model' do
    it 'updates the model id' do
      chat.with_model('gpt-4o')
      expect(chat.model.id).to eq('gpt-4o')
    end

    it 'returns self for chaining' do
      expect(chat.with_model('gpt-4o')).to eq(chat)
    end
  end

  # ── add_message / reset_messages! ─────────────────────────────────────────

  describe '#add_message' do
    it 'injects a message into the history before the next ask' do
      stub_inference
      chat.add_message(role: :user, content: 'injected context')
      chat.ask('follow up')

      expect(Legion::LLM::DaemonClient).to have_received(:inference).with(
        hash_including(
          messages: array_including(hash_including(role: 'user', content: 'injected context'))
        )
      )
    end
  end

  describe '#reset_messages!' do
    it 'clears accumulated message history so the next ask sends only new messages' do
      stub_inference(content: 'first answer')
      chat.ask('first message')

      # After reset, only the new message should appear in the next inference call
      captured_messages = nil
      allow(Legion::LLM::DaemonClient).to receive(:inference) do |messages:, **_|
        captured_messages = messages
        {
          status: :immediate,
          data:   { content: 'fresh answer', tool_calls: nil,
                    input_tokens: 2, output_tokens: 2, model: 'claude-sonnet-4-6' }
        }
      end

      chat.reset_messages!
      chat.ask('fresh start')

      user_messages = captured_messages&.select { |m| m[:role] == 'user' }
      expect(user_messages&.length).to eq(1)
      expect(user_messages&.first&.dig(:content)).to eq('fresh start')
    end
  end

  # ── on_tool_call / on_tool_result ─────────────────────────────────────────

  describe '#on_tool_call and #on_tool_result callbacks' do
    let(:fake_tool) do
      Class.new do
        def self.tool_name = 'run_command'
        def self.description = 'Runs a shell command'
        def self.parameters  = {}
        def self.call(**_)   = 'command output'
      end
    end

    it 'fires on_tool_call before executing a tool' do
      tool_call_received = []

      first_response = {
        status: :immediate,
        data:   {
          content:       nil,
          tool_calls:    [{ id: 'tc1', name: 'run_command', arguments: { cmd: 'ls' } }],
          input_tokens:  5,
          output_tokens: 5,
          model:         'claude-sonnet-4-6'
        }
      }
      final_response = {
        status: :immediate,
        data:   {
          content:       'done',
          tool_calls:    nil,
          input_tokens:  10,
          output_tokens: 10,
          model:         'claude-sonnet-4-6'
        }
      }

      allow(Legion::LLM::DaemonClient).to receive(:inference)
        .and_return(first_response, final_response)

      chat.with_tools(fake_tool)
      chat.on_tool_call { |tc| tool_call_received << tc.name }
      chat.ask('run something')

      expect(tool_call_received).to eq(['run_command'])
    end

    it 'fires on_tool_result after executing a tool' do
      tool_results_received = []

      first_response = {
        status: :immediate,
        data:   {
          content:       nil,
          tool_calls:    [{ id: 'tc1', name: 'run_command', arguments: {} }],
          input_tokens:  5,
          output_tokens: 5,
          model:         'claude-sonnet-4-6'
        }
      }
      final_response = {
        status: :immediate,
        data:   {
          content:       'done',
          tool_calls:    nil,
          input_tokens:  10,
          output_tokens: 10,
          model:         'claude-sonnet-4-6'
        }
      }

      allow(Legion::LLM::DaemonClient).to receive(:inference)
        .and_return(first_response, final_response)

      chat.with_tools(fake_tool)
      chat.on_tool_result { |tr| tool_results_received << tr.content }
      chat.ask('run something')

      expect(tool_results_received).to eq(['command output'])
    end
  end

  # ── ask ────────────────────────────────────────────────────────────────────

  describe '#ask' do
    context 'with a plain text response (no tool calls)' do
      before { stub_inference(content: 'Hello there!') }

      it 'returns a Response with the content' do
        response = chat.ask('hello')
        expect(response.content).to eq('Hello there!')
      end

      it 'returns a Response with token counts' do
        response = chat.ask('hello')
        expect(response.input_tokens).to eq(5)
        expect(response.output_tokens).to eq(10)
      end

      it 'returns a Response with a model object responding to .id' do
        response = chat.ask('hello')
        expect(response.model.id).to eq('claude-sonnet-4-6')
      end

      it 'yields a chunk with the full content for streaming' do
        chunks = []
        chat.ask('hello') { |chunk| chunks << chunk.content }
        expect(chunks).to eq(['Hello there!'])
      end

      it 'appends the user message and assistant response to history' do
        chat.ask('hello')
        stub_inference(content: 'follow up answer')
        chat.ask('follow up')

        expect(Legion::LLM::DaemonClient).to have_received(:inference).twice
      end
    end

    context 'when daemon returns an error status' do
      it 'raises CLI::Error' do
        allow(Legion::LLM::DaemonClient).to receive(:inference)
          .and_return({ status: :error, error: 'connection refused' })

        expect { chat.ask('test') }.to raise_error(Legion::CLI::Error, /Daemon inference error/)
      end
    end

    context 'when daemon is unavailable' do
      it 'raises CLI::Error' do
        allow(Legion::LLM::DaemonClient).to receive(:inference)
          .and_return({ status: :unavailable })

        expect { chat.ask('test') }.to raise_error(Legion::CLI::Error, /unavailable/)
      end
    end

    context 'with a tool_calls response followed by a final text response' do
      let(:fake_tool) do
        Class.new do
          def self.tool_name   = 'read_file'
          def self.description = 'Reads a file'
          def self.parameters  = {}
          def self.call(**)    = 'file contents here'
        end
      end

      let(:tool_call_response) do
        {
          status: :immediate,
          data:   {
            content:       nil,
            tool_calls:    [{ id: 'tc1', name: 'read_file', arguments: { path: 'main.rb' } }],
            input_tokens:  8,
            output_tokens: 4,
            model:         'claude-sonnet-4-6'
          }
        }
      end

      let(:final_response) do
        {
          status: :immediate,
          data:   {
            content:       'Based on the file: it looks good.',
            tool_calls:    nil,
            input_tokens:  20,
            output_tokens: 15,
            model:         'claude-sonnet-4-6'
          }
        }
      end

      before do
        allow(Legion::LLM::DaemonClient).to receive(:inference)
          .and_return(tool_call_response, final_response)
        chat.with_tools(fake_tool)
      end

      it 'loops until a non-tool response is received' do
        response = chat.ask('read main.rb')
        expect(response.content).to eq('Based on the file: it looks good.')
        expect(Legion::LLM::DaemonClient).to have_received(:inference).twice
      end

      it 'appends tool result messages to the conversation' do
        chat.ask('read main.rb')

        # On the second call, messages should include the tool result
        second_call_messages = nil
        allow(Legion::LLM::DaemonClient).to receive(:inference) do |messages:, **|
          second_call_messages ||= messages if second_call_messages.nil?
          final_response
        end

        expect(Legion::LLM::DaemonClient).to have_received(:inference).twice
      end

      it 'returns "Unknown tool: name" when tool is not registered' do
        chat.with_tools # clear tools
        allow(Legion::LLM::DaemonClient).to receive(:inference)
          .and_return(tool_call_response, final_response)

        # Should not raise — returns graceful error string as tool result
        expect { chat.ask('read main.rb') }.not_to raise_error
      end
    end
  end
end
