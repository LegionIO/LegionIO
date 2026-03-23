# frozen_string_literal: true

require 'legion/cli/chat_command'

begin
  require 'ruby_llm'

  require 'legion/cli/chat/tools/read_file'
  require 'legion/cli/chat/tools/write_file'
  require 'legion/cli/chat/tools/edit_file'
  require 'legion/cli/chat/tools/search_files'
  require 'legion/cli/chat/tools/search_content'
  require 'legion/cli/chat/tools/run_command'
  require 'legion/cli/chat/tools/save_memory'
  require 'legion/cli/chat/tools/search_memory'
  require 'legion/cli/chat/tools/web_search'
  require 'legion/cli/chat/tools/spawn_agent'
  require 'legion/cli/chat/tools/search_traces'
rescue LoadError => e
  Legion::Logging.debug("ToolRegistry ruby_llm not available, chat tools will not be registered: #{e.message}") if defined?(Legion::Logging)
end

require 'legion/cli/chat/permissions'

module Legion
  module CLI
    class Chat
      module ToolRegistry
        BUILTIN_TOOLS = if defined?(Tools::ReadFile)
                          [
                            Tools::ReadFile,
                            Tools::WriteFile,
                            Tools::EditFile,
                            Tools::SearchFiles,
                            Tools::SearchContent,
                            Tools::RunCommand,
                            Tools::SaveMemory,
                            Tools::SearchMemory,
                            Tools::WebSearch,
                            Tools::SpawnAgent,
                            Tools::SearchTraces
                          ].freeze
                        else
                          [].freeze
                        end

        Permissions.apply!(BUILTIN_TOOLS) unless BUILTIN_TOOLS.empty?

        def self.builtin_tools
          BUILTIN_TOOLS.dup
        end

        def self.all_tools
          require 'legion/cli/chat/extension_tool_loader'
          builtin_tools + ExtensionToolLoader.discover
        rescue LoadError => e
          Legion::Logging.debug("ToolRegistry#all_tools ExtensionToolLoader not available: #{e.message}") if defined?(Legion::Logging)
          builtin_tools
        end
      end
    end
  end
end
