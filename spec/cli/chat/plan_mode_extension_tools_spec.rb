# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tool_registry'
require 'legion/cli/chat/extension_tool'

RSpec.describe 'Plan mode with extension tools' do
  let(:read_ext_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'Read ext tool'
      permission_tier :read
    end
  end

  let(:write_ext_tool) do
    Class.new(RubyLLM::Tool) do
      include Legion::CLI::Chat::ExtensionTool
      description 'Write ext tool'
      permission_tier :write
    end
  end

  after { Legion::CLI::Chat::Permissions.clear_extension_tiers! }

  it 'read-tier extension tools survive plan mode filtering' do
    perms = Legion::CLI::Chat::Permissions
    perms.register_extension_tier(read_ext_tool, :read)
    perms.register_extension_tier(write_ext_tool, :write)

    all_tools = [
      Legion::CLI::Chat::Tools::ReadFile,
      Legion::CLI::Chat::Tools::WriteFile,
      read_ext_tool,
      write_ext_tool
    ]

    # Plan mode keeps only read-tier tools
    plan_tools = all_tools.select do |t|
      perms.tier_for(t) == :read
    end

    expect(plan_tools).to include(Legion::CLI::Chat::Tools::ReadFile)
    expect(plan_tools).to include(read_ext_tool)
    expect(plan_tools).not_to include(Legion::CLI::Chat::Tools::WriteFile)
    expect(plan_tools).not_to include(write_ext_tool)
  end

  it 'write-tier extension tools are excluded in plan mode' do
    perms = Legion::CLI::Chat::Permissions
    perms.register_extension_tier(write_ext_tool, :write)

    plan_tools = [write_ext_tool].select { |t| perms.tier_for(t) == :read }
    expect(plan_tools).to be_empty
  end
end
