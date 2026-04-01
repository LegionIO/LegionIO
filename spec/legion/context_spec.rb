# frozen_string_literal: true

require 'spec_helper'
require 'legion/context'

RSpec.describe Legion::Context do
  after { described_class.end_session }

  describe '.with_session' do
    it 'sets and restores session' do
      ctx = Legion::Context::SessionContext.new(user_id: 'test')
      inner = nil
      described_class.with_session(ctx) { inner = described_class.current_session }
      expect(inner.user_id).to eq('test')
      expect(described_class.current_session).to be_nil
    end
  end

  describe '.start_session' do
    it 'creates session with uuid' do
      ctx = described_class.start_session(user_id: 'user-1')
      expect(ctx.session_id).to match(/\A[0-9a-f-]{36}\z/)
      expect(described_class.current_session).to eq(ctx)
    end
  end

  describe '.session_metadata' do
    it 'returns empty hash without session' do
      expect(described_class.session_metadata).to eq({})
    end

    it 'returns metadata with session' do
      described_class.start_session(user_id: 'u1')
      meta = described_class.session_metadata
      expect(meta[:user_id]).to eq('u1')
      expect(meta[:session_id]).not_to be_nil
    end
  end

  describe '.end_session' do
    it 'clears current session' do
      described_class.start_session
      described_class.end_session
      expect(described_class.current_session).to be_nil
    end
  end

  describe '.with_task_context' do
    after { Thread.current[:legion_context] = nil }

    it 'sets thread-local context from message hash' do
      message = { task_id: 42, conversation_id: 'conv-1', chain_id: 7, function: 'get', runner_class: 'Foo' }
      captured = nil
      described_class.with_task_context(message) { captured = Thread.current[:legion_context] }
      expect(captured).to eq(message.slice(:task_id, :conversation_id, :chain_id, :function, :runner_class))
    end

    it 'compacts nil values' do
      described_class.with_task_context({ task_id: nil, function: 'get' }) do
        expect(Thread.current[:legion_context]).to eq({ function: 'get' })
      end
    end

    it 'restores previous context in ensure' do
      Thread.current[:legion_context] = { task_id: 99 }
      described_class.with_task_context({ task_id: 1 }) do
        expect(Thread.current[:legion_context][:task_id]).to eq(1)
      end
      expect(Thread.current[:legion_context][:task_id]).to eq(99)
    end

    it 'restores on exception' do
      described_class.with_task_context({ task_id: 1 }) { raise 'boom' }
    rescue RuntimeError
      nil
    ensure
      expect(Thread.current[:legion_context]).to be_nil
    end
  end

  describe '.current_task_context' do
    it 'returns nil when no context set' do
      expect(described_class.current_task_context).to be_nil
    end

    it 'returns the current task context' do
      Thread.current[:legion_context] = { task_id: 5 }
      expect(described_class.current_task_context).to eq({ task_id: 5 })
    ensure
      Thread.current[:legion_context] = nil
    end
  end
end
