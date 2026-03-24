# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Catalog::Registry do
  before { described_class.reset! }

  describe '.register' do
    it 'registers a capability' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a PR', tags: %w[github pr]
      )
      described_class.register(cap)
      expect(described_class.capabilities).to include(cap)
    end

    it 'prevents duplicates by name' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close'
      )
      described_class.register(cap)
      described_class.register(cap)
      expect(described_class.capabilities.count { |c| c.name == cap.name }).to eq(1)
    end
  end

  describe '.find' do
    it 'finds by canonical name' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close'
      )
      described_class.register(cap)
      found = described_class.find(name: cap.name)
      expect(found).to eq(cap)
    end

    it 'returns nil for unknown' do
      expect(described_class.find(name: 'nonexistent')).to be_nil
    end
  end

  describe '.find_by_intent' do
    it 'returns capabilities matching intent text' do
      cap1 = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a pull request', tags: %w[github pr close]
      )
      cap2 = Legion::Extensions::Capability.from_runner(
        extension: 'lex-jira', runner: 'Issue', function: 'create',
        description: 'Create a Jira issue', tags: %w[jira issue create]
      )
      described_class.register(cap1)
      described_class.register(cap2)

      results = described_class.find_by_intent('close pull request')
      expect(results.map(&:name)).to include(cap1.name)
      expect(results.map(&:name)).not_to include(cap2.name)
    end
  end

  describe '.for_mcp' do
    it 'returns all capabilities as MCP-exposable tools' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a PR'
      )
      described_class.register(cap)
      mcp_tools = described_class.for_mcp
      expect(mcp_tools.length).to eq(1)
      expect(mcp_tools.first).to eq(cap)
    end
  end

  describe '.for_override' do
    it 'finds capability that can override an MCP tool' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        tags: %w[github pr close]
      )
      described_class.register(cap)

      override = described_class.for_override('close')
      expect(override).to eq(cap)
    end

    it 'returns nil when no match' do
      expect(described_class.for_override('nonexistent')).to be_nil
    end
  end

  describe '.count' do
    it 'returns the number of registered capabilities' do
      expect(described_class.count).to eq(0)
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-http', runner: 'Request', function: 'get'
      )
      described_class.register(cap)
      expect(described_class.count).to eq(1)
    end
  end
end
