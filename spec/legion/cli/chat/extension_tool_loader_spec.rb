# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/extension_tool_loader'

RSpec.describe Legion::CLI::Chat::ExtensionToolLoader do
  after { described_class.reset! }

  describe '.tools_dir_for' do
    it 'appends /tools to extension path' do
      expect(described_class.tools_dir_for('/path/to/ext')).to eq('/path/to/ext/tools')
    end
  end

  describe '.tool_enabled?' do
    context 'when no settings exist' do
      before do
        allow(described_class).to receive(:extension_settings).and_return(nil)
      end

      it 'returns true' do
        expect(described_class.tool_enabled?('http')).to be true
      end
    end

    context 'when tools explicitly disabled' do
      before do
        allow(described_class).to receive(:extension_settings).and_return({ tools: { enabled: false } })
      end

      it 'returns false' do
        expect(described_class.tool_enabled?('http')).to be false
      end
    end

    context 'when tools enabled' do
      before do
        allow(described_class).to receive(:extension_settings).and_return({ tools: { enabled: true } })
      end

      it 'returns true' do
        expect(described_class.tool_enabled?('http')).to be true
      end
    end
  end

  describe '.effective_tier' do
    let(:read_tool) do
      klass = Class.new(RubyLLM::Tool)
      klass.define_singleton_method(:declared_permission_tier) { :read }
      klass
    end

    let(:write_tool) do
      klass = Class.new(RubyLLM::Tool)
      klass.define_singleton_method(:declared_permission_tier) { :write }
      klass
    end

    let(:bare_tool) { Class.new(RubyLLM::Tool) }

    before do
      allow(described_class).to receive(:settings_tier_for).and_return(nil)
    end

    it 'returns declared tier from tool class' do
      expect(described_class.effective_tier(read_tool, 'http')).to eq(:read)
    end

    it 'defaults to :write when no tier declared' do
      expect(described_class.effective_tier(bare_tool, 'http')).to eq(:write)
    end

    it 'escalates tier from settings when higher' do
      allow(described_class).to receive(:settings_tier_for).and_return(:shell)
      expect(described_class.effective_tier(read_tool, 'http')).to eq(:shell)
    end

    it 'does not downgrade tier from settings' do
      allow(described_class).to receive(:settings_tier_for).and_return(:read)
      expect(described_class.effective_tier(write_tool, 'http')).to eq(:write)
    end
  end

  describe '.collect_tool_classes' do
    it 'finds RubyLLM::Tool subclasses' do
      tools_mod = Module.new
      tool_class = Class.new(RubyLLM::Tool)
      non_tool = Class.new
      tools_mod.const_set(:MyTool, tool_class)
      tools_mod.const_set(:Helper, non_tool)

      result = described_class.collect_tool_classes(tools_mod)
      expect(result).to contain_exactly(tool_class)
    end

    it 'returns empty array when no tools' do
      tools_mod = Module.new
      expect(described_class.collect_tool_classes(tools_mod)).to eq([])
    end
  end

  describe '.discover' do
    it 'returns empty array when no extensions loaded' do
      expect(described_class.discover).to eq([])
    end

    it 'memoizes results' do
      first = described_class.discover
      second = described_class.discover
      expect(first).to equal(second)
    end
  end

  describe '.reset!' do
    it 'clears memoized discovery' do
      described_class.discover
      described_class.reset!
      # After reset, discover will re-run (returns new array object)
      expect(described_class.discover).to eq([])
    end
  end
end
