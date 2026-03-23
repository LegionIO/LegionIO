# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe 'Legion Chat Integration' do
  it 'registers chat subcommand in Main' do
    expect(Legion::CLI::Main.subcommands).to include('chat')
  end

  it 'routes piped stdin legion to chat prompt' do
    content = File.read(File.expand_path('../../../../exe/legion', __dir__))
    expect(content).to include("ARGV.replace(['chat', 'prompt', ''])")
  end

  it 'has all expected tools registered' do
    require 'legion/cli/chat/tool_registry'
    tools = Legion::CLI::Chat::ToolRegistry.builtin_tools
    expect(tools.length).to eq(19)

    tool_classes = tools.map(&:name)
    expect(tool_classes).to include(a_string_matching(/ReadFile/))
    expect(tool_classes).to include(a_string_matching(/WriteFile/))
    expect(tool_classes).to include(a_string_matching(/EditFile/))
    expect(tool_classes).to include(a_string_matching(/SearchFiles/))
    expect(tool_classes).to include(a_string_matching(/SearchContent/))
    expect(tool_classes).to include(a_string_matching(/RunCommand/))
    expect(tool_classes).to include(a_string_matching(/SaveMemory/))
    expect(tool_classes).to include(a_string_matching(/SearchMemory/))
    expect(tool_classes).to include(a_string_matching(/SearchTraces/))
    expect(tool_classes).to include(a_string_matching(/QueryKnowledge/))
    expect(tool_classes).to include(a_string_matching(/IngestKnowledge/))
    expect(tool_classes).to include(a_string_matching(/ConsolidateMemory/))
    expect(tool_classes).to include(a_string_matching(/RelateKnowledge/))
    expect(tool_classes).to include(a_string_matching(/KnowledgeMaintenance/))
    expect(tool_classes).to include(a_string_matching(/KnowledgeStats/))
    expect(tool_classes).to include(a_string_matching(/SummarizeTraces/))
    expect(tool_classes).to include(a_string_matching(/ListExtensions/))
    expect(tool_classes).to include(a_string_matching(/WebSearch/))
    expect(tool_classes).to include(a_string_matching(/SpawnAgent/))
  end

  it 'context detects current project as ruby' do
    require 'legion/cli/chat/context'
    project_root = File.expand_path('../../../..', __dir__)
    ctx = Legion::CLI::Chat::Context.detect(project_root)
    expect(ctx[:project_type]).to eq(:ruby)
  end

  it 'Chat has interactive as default task' do
    expect(Legion::CLI::Chat.default_command).to eq('interactive')
  end

  it 'Main has ask command for -p shortcut' do
    expect(Legion::CLI::Main.all_commands).to have_key('ask')
  end
end
