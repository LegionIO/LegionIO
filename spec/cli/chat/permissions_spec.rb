# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tool_registry'
require 'legion/cli/chat/extension_tool'

RSpec.describe Legion::CLI::Chat::Permissions do
  let(:read_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'Read tool'
      permission_tier :read
    end
  end

  let(:write_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'Write tool'
      permission_tier :write
    end
  end

  after { described_class.clear_extension_tiers! }

  describe '.register_extension_tier' do
    it 'registers a tier for an extension tool class' do
      described_class.register_extension_tier(read_tool, :read)
      expect(described_class.tier_for(read_tool)).to eq(:read)
    end
  end

  describe '.tier_for with extension tools' do
    it 'returns :read for registered read-tier extension tools' do
      described_class.register_extension_tier(read_tool, :read)
      expect(described_class.tier_for(read_tool)).to eq(:read)
    end

    it 'returns :write for registered write-tier extension tools' do
      described_class.register_extension_tier(write_tool, :write)
      expect(described_class.tier_for(write_tool)).to eq(:write)
    end

    it 'returns :read for unregistered tools (default fallback)' do
      expect(described_class.tier_for(read_tool)).to eq(:read)
    end
  end

  describe '.tier_for with builtin tools' do
    it 'returns :read for ReadFile' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::ReadFile)).to eq(:read)
    end

    it 'returns :write for WriteFile' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::WriteFile)).to eq(:write)
    end

    it 'returns :shell for RunCommand' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::RunCommand)).to eq(:shell)
    end
  end
end
