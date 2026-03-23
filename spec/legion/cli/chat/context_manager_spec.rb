# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/context_manager'

RSpec.describe Legion::CLI::Chat::ContextManager do
  let(:messages) do
    [
      double('msg1', to_h: { role: :user, content: 'How does caching work in Legion?' }),
      double('msg2', to_h: { role: :assistant, content: 'Legion uses Redis or Memcached via legion-cache.' }),
      double('msg3', to_h: { role: :user, content: 'What about persistence?' }),
      double('msg4', to_h: { role: :assistant, content: 'Legion-data supports SQLite, PostgreSQL, and MySQL via Sequel.' })
    ]
  end

  let(:chat) do
    chat = double('chat')
    allow(chat).to receive(:messages).and_return(messages)
    allow(chat).to receive(:reset_messages!)
    allow(chat).to receive(:add_message)
    chat
  end

  let(:session) do
    session = double('session')
    allow(session).to receive(:chat).and_return(chat)
    session
  end

  describe '.stats' do
    it 'returns message statistics' do
      result = described_class.stats(session)
      expect(result[:message_count]).to eq(4)
      expect(result[:char_count]).to be > 0
      expect(result[:estimated_tokens]).to be > 0
      expect(result[:by_role]).to include('user' => 2, 'assistant' => 2)
    end
  end

  describe '.should_auto_compact?' do
    it 'returns false for short conversations' do
      expect(described_class.should_auto_compact?(session)).to be false
    end

    it 'returns true when messages exceed threshold' do
      long_messages = 50.times.map { |i| double("msg#{i}", to_h: { role: :user, content: "Message #{i}" }) }
      allow(chat).to receive(:messages).and_return(long_messages)
      expect(described_class.should_auto_compact?(session)).to be true
    end
  end

  describe '.compact' do
    it 'returns too_few_messages for short conversations' do
      short_messages = [double('msg', to_h: { role: :user, content: 'hi' })]
      allow(chat).to receive(:messages).and_return(short_messages)
      result = described_class.compact(session)
      expect(result[:compacted]).to be false
      expect(result[:reason]).to eq('too_few_messages')
    end

    context 'with dedup strategy' do
      it 'removes duplicates when compressor is available' do
        stub_const('Legion::LLM::Compressor', Module.new)
        allow(Legion::LLM::Compressor).to receive(:deduplicate_messages).and_return(
          { messages: [messages[1].to_h, messages[2].to_h, messages[3].to_h], removed: 1, original_count: 4 }
        )

        result = described_class.compact(session, strategy: :dedup)
        expect(result[:compacted]).to be true
        expect(result[:strategy]).to eq(:dedup)
        expect(result[:removed]).to eq(1)
      end

      it 'reports no duplicates found' do
        stub_const('Legion::LLM::Compressor', Module.new)
        allow(Legion::LLM::Compressor).to receive(:deduplicate_messages).and_return(
          { messages: messages.map(&:to_h), removed: 0, original_count: 4 }
        )

        result = described_class.compact(session, strategy: :dedup)
        expect(result[:compacted]).to be false
        expect(result[:reason]).to eq('no_duplicates')
      end
    end

    context 'with summarize strategy' do
      it 'uses LLM compressor summarization' do
        stub_const('Legion::LLM::Compressor', Module.new)
        allow(Legion::LLM::Compressor).to receive(:summarize_messages).and_return(
          { summary: 'Discussion about caching and persistence in Legion.', compressed: true, original_count: 4 }
        )

        result = described_class.compact(session, strategy: :summarize)
        expect(result[:compacted]).to be true
        expect(result[:strategy]).to eq(:summarize)
        expect(result[:final_count]).to eq(1)
      end

      it 'reports unavailable when compressor missing' do
        result = described_class.compact(session, strategy: :summarize)
        expect(result[:compacted]).to be false
        expect(result[:reason]).to eq('summarization_unavailable')
      end
    end

    context 'with auto strategy' do
      it 'runs dedup and returns results' do
        stub_const('Legion::LLM::Compressor', Module.new)
        allow(Legion::LLM::Compressor).to receive(:deduplicate_messages).and_return(
          { messages: messages.map(&:to_h), removed: 0, original_count: 4 }
        )

        result = described_class.compact(session, strategy: :auto)
        expect(result[:strategy]).to eq(:auto)
        expect(result[:final_count]).to eq(4)
      end
    end

    it 'returns unknown_strategy for invalid strategy' do
      result = described_class.compact(session, strategy: :invalid)
      expect(result[:compacted]).to be false
      expect(result[:reason]).to eq('unknown_strategy')
    end
  end
end
