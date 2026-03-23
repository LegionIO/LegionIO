# frozen_string_literal: true

require 'spec_helper'

require 'legion/cli/chat/tool_registry'
require 'legion/cli/chat/extension_tool_loader'

RSpec.describe Legion::CLI::Chat::ToolRegistry do
  describe '.builtin_tools' do
    it 'returns 32 built-in tools' do
      expect(described_class.builtin_tools.length).to eq(32)
    end
  end

  describe '.all_tools' do
    before { Legion::CLI::Chat::ExtensionToolLoader.reset! }

    it 'includes builtin tools' do
      expect(described_class.all_tools).to include(*described_class.builtin_tools)
    end

    it 'includes extension tools when available' do
      fake_tool = Class.new(RubyLLM::Tool) do
        description 'Fake extension tool'
        def execute = 'ok'
      end
      allow(Legion::CLI::Chat::ExtensionToolLoader).to receive(:discover).and_return([fake_tool])

      tools = described_class.all_tools
      expect(tools).to include(fake_tool)
      expect(tools.length).to eq(33)
    end
  end
end
