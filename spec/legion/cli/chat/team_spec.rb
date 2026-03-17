# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/team'

RSpec.describe Legion::CLI::Chat::Team do
  after { Thread.current[:legion_chat_user] = nil }

  describe '.with_user' do
    it 'sets and restores user context' do
      ctx = Legion::CLI::Chat::Team::UserContext.new(user_id: 'test')
      inner = nil
      described_class.with_user(ctx) { inner = described_class.current_user }
      expect(inner.user_id).to eq('test')
      expect(described_class.current_user).to be_nil
    end

    it 'restores context on exception' do
      ctx = Legion::CLI::Chat::Team::UserContext.new(user_id: 'test')
      begin
        described_class.with_user(ctx) { raise 'boom' }
      rescue RuntimeError
        nil
      end
      expect(described_class.current_user).to be_nil
    end
  end

  describe '.detect_user' do
    it 'returns UserContext from env' do
      user = described_class.detect_user
      expect(user).to be_a(Legion::CLI::Chat::Team::UserContext)
      expect(user.user_id).not_to be_nil
    end
  end

  describe '.current_user' do
    it 'returns nil when no user set' do
      expect(described_class.current_user).to be_nil
    end
  end
end

RSpec.describe Legion::CLI::Chat::Team::UserContext do
  let(:ctx) { described_class.new(user_id: 'u1', team_id: 't1') }

  it 'has correct attributes' do
    expect(ctx.user_id).to eq('u1')
    expect(ctx.team_id).to eq('t1')
    expect(ctx.display_name).to eq('u1')
  end

  it 'serializes to hash' do
    h = ctx.to_h
    expect(h[:user_id]).to eq('u1')
    expect(h[:team_id]).to eq('t1')
  end

  it 'uses custom display_name' do
    ctx = described_class.new(user_id: 'u1', display_name: 'User One')
    expect(ctx.display_name).to eq('User One')
  end
end
