# frozen_string_literal: true

require 'spec_helper'

begin
  require 'ruby_llm'
rescue LoadError
  # ruby_llm not available
end

require 'legion/cli/chat/extension_tool'
require 'legion/cli/chat/extension_tool_loader'

RSpec.describe Legion::CLI::Chat::ExtensionToolLoader, skip: !defined?(RubyLLM) && 'requires ruby_llm' do
  before do
    described_class.reset!
  end

  describe '.discover' do
    it 'returns an array' do
      expect(described_class.discover).to be_an(Array)
    end

    it 'returns empty array when no extensions are loaded' do
      allow(described_class).to receive(:loaded_extension_paths).and_return([])
      expect(described_class.discover).to eq([])
    end
  end

  describe '.tools_dir_for' do
    it 'returns the tools directory path for an extension' do
      path = described_class.tools_dir_for('/fake/lib/legion/extensions/redis')
      expect(path).to eq('/fake/lib/legion/extensions/redis/tools')
    end
  end

  describe '.collect_tool_classes' do
    it 'collects RubyLLM::Tool subclasses from a module' do
      mod = Module.new
      tool_class = Class.new(RubyLLM::Tool) do
        include Legion::CLI::Chat::ExtensionTool

        description 'Test tool'
        permission_tier :read
        def execute = 'ok'
      end
      allow(mod).to receive(:constants).and_return([:TestTool])
      allow(mod).to receive(:const_get).with(:TestTool).and_return(tool_class)

      tools = described_class.collect_tool_classes(mod)
      expect(tools).to eq([tool_class])
    end

    it 'skips non-Tool classes' do
      mod = Module.new
      not_a_tool = Class.new
      allow(mod).to receive(:constants).and_return([:NotATool])
      allow(mod).to receive(:const_get).with(:NotATool).and_return(not_a_tool)

      expect(described_class.collect_tool_classes(mod)).to eq([])
    end
  end

  describe '.tool_enabled?' do
    it 'returns true by default' do
      expect(described_class.tool_enabled?('redis')).to be true
    end

    it 'returns false when tools.enabled is false in settings' do
      allow(described_class).to receive(:extension_settings).with('redis').and_return({ tools: { enabled: false } })
      expect(described_class.tool_enabled?('redis')).to be false
    end
  end

  describe '.effective_tier' do
    let(:tool_class) do
      Class.new(RubyLLM::Tool) do
        include Legion::CLI::Chat::ExtensionTool

        description 'Test'
        permission_tier :read
      end
    end

    it 'returns the class-declared tier when no settings override' do
      expect(described_class.effective_tier(tool_class, 'redis')).to eq(:read)
    end

    it 'returns the settings override when it is more restrictive' do
      allow(described_class).to receive(:settings_tier_for).and_return(:shell)
      expect(described_class.effective_tier(tool_class, 'redis')).to eq(:shell)
    end
  end
end
