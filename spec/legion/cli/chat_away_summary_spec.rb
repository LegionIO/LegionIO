# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe 'Chat away summary' do
  let(:chat_instance) { Legion::CLI::Chat.new }

  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  describe '#away?' do
    it 'returns false when last_active_at is nil' do
      expect(chat_instance.send(:away?)).to be false
    end

    it 'returns false when idle less than threshold' do
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 10)
      allow(chat_instance).to receive(:chat_setting).and_return(120)
      expect(chat_instance.send(:away?)).to be false
    end

    it 'returns true when idle exceeds threshold' do
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 300)
      allow(chat_instance).to receive(:chat_setting).and_return(120)
      expect(chat_instance.send(:away?)).to be true
    end

    it 'uses default threshold of 120 seconds when not configured' do
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 130)
      allow(chat_instance).to receive(:chat_setting).and_return(nil)
      expect(chat_instance.send(:away?)).to be true
    end
  end

  describe '#show_away_summary' do
    let(:out) { instance_double(Legion::CLI::Output::Formatter, colorize: '[away]', dim: '') }

    it 'does nothing when Legion::LLM is not defined' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 300)
      expect { chat_instance.send(:show_away_summary, out) }.not_to raise_error
    end

    it 'does nothing when session has fewer than 2 messages' do
      stub_const('Legion::LLM', Module.new do
        def self.respond_to?(name, *)
          name == :chat_direct ? true : super
        end

        def self.chat_direct(**) = nil
      end)

      mock_messages = [double(role: 'user', content: 'hello')]
      mock_chat = double(messages: mock_messages)
      mock_session = double(chat: mock_chat)
      chat_instance.instance_variable_set(:@session, mock_session)
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 300)

      expect { chat_instance.send(:show_away_summary, out) }.not_to raise_error
    end

    it 'does not raise on LLM errors' do
      stub_const('Legion::LLM', Module.new do
        def self.respond_to?(name, *)
          name == :chat_direct ? true : super
        end

        def self.chat_direct(**)
          raise StandardError, 'provider unavailable'
        end
      end)

      mock_messages = [
        double(role: 'user', content: 'hello'),
        double(role: 'assistant', content: 'hi there')
      ]
      mock_chat = double(messages: mock_messages)
      mock_session = double(chat: mock_chat)
      chat_instance.instance_variable_set(:@session, mock_session)
      chat_instance.instance_variable_set(:@last_active_at, Time.now - 300)

      expect { chat_instance.send(:show_away_summary, out) }.not_to raise_error
    end
  end
end
