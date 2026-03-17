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
end
