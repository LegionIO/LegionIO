# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ostruct'
require 'legion/cli/error'

# Stub RubyLLM::Chat if not already defined
unless defined?(RubyLLM::Chat)
  module RubyLLM
    class Message
      attr_reader :role, :content, :model_id, :tool_calls, :tool_call_id

      def initialize(opts = {})
        @role = opts[:role]&.to_sym
        @content = opts[:content]
        @model_id = opts[:model_id]
        @tool_calls = opts[:tool_calls]
        @tool_call_id = opts[:tool_call_id]
      end

      def to_h
        { role: role, content: content, model_id: model_id }.compact
      end
    end

    class Chat
      attr_reader :messages

      def initialize(**)
        @messages = []
      end

      def add_message(msg)
        message = msg.is_a?(Message) ? msg : Message.new(msg)
        @messages << message
        message
      end

      def reset_messages!
        @messages.clear
      end

      def model
        OpenStruct.new(id: 'test-model')
      end

      def with_instructions(_text) = self
    end
  end
end

require 'legion/cli/chat/session_store'
require 'legion/cli/chat/session'

RSpec.describe Legion::CLI::Chat::SessionStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:chat) { RubyLLM::Chat.new }
  let(:session) { Legion::CLI::Chat::Session.new(chat: chat) }

  before do
    stub_const('Legion::CLI::Chat::SessionStore::SESSIONS_DIR', tmpdir)
    chat.add_message(role: :user, content: 'hello')
    chat.add_message(role: :assistant, content: 'hi there')
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe '.save' do
    it 'writes session to a JSON file' do
      path = described_class.save(session, 'test-session')
      expect(File.exist?(path)).to be true
      expect(path).to end_with('test-session.json')
    end

    it 'includes messages in the saved data' do
      described_class.save(session, 'test-session')
      data = Legion::JSON.load(File.read(described_class.session_path('test-session')))
      expect(data[:messages].length).to eq(2)
      expect(data[:messages][0][:role].to_s).to eq('user')
      expect(data[:messages][0][:content]).to eq('hello')
      expect(data[:messages][1][:role].to_s).to eq('assistant')
    end

    it 'includes metadata' do
      described_class.save(session, 'test-session')
      data = Legion::JSON.load(File.read(described_class.session_path('test-session')))
      expect(data[:name]).to eq('test-session')
      expect(data[:model]).to eq('test-model')
      expect(data[:saved_at]).to be_a(String)
    end

    it 'creates sessions directory if missing' do
      FileUtils.rm_rf(tmpdir)
      described_class.save(session, 'test-session')
      expect(Dir.exist?(tmpdir)).to be true
    end
  end

  describe '.load' do
    it 'reads a saved session' do
      described_class.save(session, 'my-session')
      data = described_class.load('my-session')
      expect(data[:messages].length).to eq(2)
      expect(data[:name]).to eq('my-session')
    end

    it 'raises CLI::Error for missing session' do
      expect { described_class.load('nonexistent') }
        .to raise_error(Legion::CLI::Error, /not found/)
    end
  end

  describe '.restore' do
    it 'replaces chat messages with loaded data' do
      described_class.save(session, 'restore-test')
      data = described_class.load('restore-test')

      chat.add_message(role: :user, content: 'extra message')
      expect(chat.messages.length).to eq(3)

      described_class.restore(session, data)
      expect(chat.messages.length).to eq(2)
      expect(chat.messages[0].role).to eq(:user)
      expect(chat.messages[1].role).to eq(:assistant)
    end
  end

  describe '.list' do
    it 'returns empty array when no sessions exist' do
      FileUtils.rm_rf(tmpdir)
      expect(described_class.list).to eq([])
    end

    it 'lists saved sessions sorted by most recent' do
      described_class.save(session, 'older')
      sleep 0.05
      described_class.save(session, 'newer')

      sessions = described_class.list
      expect(sessions.length).to eq(2)
      expect(sessions[0][:name]).to eq('newer')
      expect(sessions[1][:name]).to eq('older')
    end
  end

  describe '.delete' do
    it 'removes a saved session' do
      described_class.save(session, 'deleteme')
      expect(File.exist?(described_class.session_path('deleteme'))).to be true

      described_class.delete('deleteme')
      expect(File.exist?(described_class.session_path('deleteme'))).to be false
    end

    it 'raises CLI::Error for missing session' do
      expect { described_class.delete('nonexistent') }
        .to raise_error(Legion::CLI::Error, /not found/)
    end
  end
end
