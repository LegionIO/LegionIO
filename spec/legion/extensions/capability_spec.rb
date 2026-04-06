# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/capability'

RSpec.describe Legion::Extensions::Capability do
  describe '.from_runner' do
    it 'creates a capability from runner metadata' do
      cap = described_class.from_runner(
        extension:   'lex-github',
        runner:      'PullRequest',
        function:    'close',
        description: 'Close a pull request',
        parameters:  { pr_id: { type: :integer, required: true } },
        tags:        %w[github pr write]
      )

      expect(cap.name).to eq('lex-github:pull_request:close')
      expect(cap.extension).to eq('lex-github')
      expect(cap.runner).to eq('PullRequest')
      expect(cap.function).to eq('close')
      expect(cap.description).to eq('Close a pull request')
      expect(cap.tags).to eq(%w[github pr write])
      expect(cap.frozen?).to eq(true)
    end

    it 'generates canonical name from extension:runner:function' do
      cap = described_class.from_runner(
        extension: 'lex-http', runner: 'Request', function: 'get'
      )
      expect(cap.name).to eq('lex-http:request:get')
    end
  end

  describe '#matches_intent?' do
    it 'matches on keyword overlap' do
      cap = described_class.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a GitHub pull request',
        tags: %w[github pr close]
      )

      expect(cap.matches_intent?('close pull request')).to eq(true)
      expect(cap.matches_intent?('create jira ticket')).to eq(false)
    end
  end

  describe '#to_mcp_tool' do
    it 'converts to MCP tool definition hash' do
      cap = described_class.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a pull request',
        parameters: { pr_id: { type: 'integer', description: 'PR number' } }
      )

      tool = cap.to_mcp_tool
      expect(tool[:name]).to eq('legion.github.pull_request.close')
      expect(tool[:description]).to eq('Close a pull request')
      expect(tool[:input_schema]).to have_key(:properties)
    end
  end
end
