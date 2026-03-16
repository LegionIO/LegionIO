# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/extension_tool'

RSpec.describe Legion::CLI::Chat::ExtensionTool do
  let(:read_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'A read tool'
      permission_tier :read
    end
  end

  let(:default_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'A default tool'
    end
  end

  let(:shell_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'A shell tool'
      permission_tier :shell
    end
  end

  it 'returns the declared tier' do
    expect(read_tool.declared_permission_tier).to eq(:read)
  end

  it 'defaults to :write when no tier declared' do
    expect(default_tool.declared_permission_tier).to eq(:write)
  end

  it 'supports :shell tier' do
    expect(shell_tool.declared_permission_tier).to eq(:shell)
  end

  it 'rejects invalid tiers' do
    expect do
      Class.new(RubyLLM::Tool) do
        include Legion::CLI::Chat::ExtensionTool
        permission_tier :admin
      end
    end.to raise_error(ArgumentError, /invalid permission tier/i)
  end
end
