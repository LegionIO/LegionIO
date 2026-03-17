# frozen_string_literal: true

require 'spec_helper'
require 'legion/isolation'

RSpec.describe Legion::Isolation::Context do
  let(:ctx) { described_class.new(agent_id: 'bot-1', tenant_id: 'askid-123', allowed_tools: ['read_file']) }

  describe '#tool_allowed?' do
    it 'allows listed tools' do
      expect(ctx.tool_allowed?('read_file')).to be true
    end

    it 'denies unlisted tools' do
      expect(ctx.tool_allowed?('delete_all')).to be false
    end

    it 'allows all when empty' do
      open_ctx = described_class.new(agent_id: 'bot-2')
      expect(open_ctx.tool_allowed?('anything')).to be true
    end
  end

  describe '#data_filter' do
    it 'includes agent_id and tenant_id' do
      expect(ctx.data_filter).to eq({ agent_id: 'bot-1', tenant_id: 'askid-123' })
    end

    it 'excludes tenant_id when nil' do
      ctx_no_tenant = described_class.new(agent_id: 'bot-2')
      expect(ctx_no_tenant.data_filter).to eq({ agent_id: 'bot-2' })
    end
  end

  describe '#risk_tier' do
    it 'defaults to standard' do
      expect(ctx.risk_tier).to eq(:standard)
    end

    it 'accepts custom tier' do
      high = described_class.new(agent_id: 'bot', risk_tier: :high)
      expect(high.risk_tier).to eq(:high)
    end
  end
end

RSpec.describe Legion::Isolation do
  after { Thread.current[:legion_isolation_context] = nil }

  describe '.with_context' do
    it 'sets and restores context' do
      ctx = Legion::Isolation::Context.new(agent_id: 'test')
      inner_ctx = nil
      described_class.with_context(ctx) { inner_ctx = described_class.current }
      expect(inner_ctx).to eq(ctx)
      expect(described_class.current).to be_nil
    end

    it 'restores previous context on exception' do
      ctx = Legion::Isolation::Context.new(agent_id: 'test')
      begin
        described_class.with_context(ctx) { raise 'boom' }
      rescue RuntimeError
        nil
      end
      expect(described_class.current).to be_nil
    end
  end

  describe '.enforce_tool_access!' do
    it 'raises for unauthorized tool' do
      ctx = Legion::Isolation::Context.new(agent_id: 'bot', allowed_tools: ['safe_tool'])
      described_class.with_context(ctx) do
        expect { described_class.enforce_tool_access!('dangerous') }.to raise_error(SecurityError)
      end
    end

    it 'passes without context' do
      expect(described_class.enforce_tool_access!('anything')).to be true
    end

    it 'passes for allowed tool' do
      ctx = Legion::Isolation::Context.new(agent_id: 'bot', allowed_tools: ['read_file'])
      described_class.with_context(ctx) do
        expect(described_class.enforce_tool_access!('read_file')).to be true
      end
    end
  end
end
