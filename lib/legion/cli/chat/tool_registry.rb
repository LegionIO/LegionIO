# frozen_string_literal: true

require 'legion/cli/chat/tools/read_file'
require 'legion/cli/chat/tools/write_file'
require 'legion/cli/chat/tools/edit_file'
require 'legion/cli/chat/tools/search_files'
require 'legion/cli/chat/tools/search_content'
require 'legion/cli/chat/tools/run_command'

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      module ToolRegistry
        BUILTIN_TOOLS = [
          Tools::ReadFile,
          Tools::WriteFile,
          Tools::EditFile,
          Tools::SearchFiles,
          Tools::SearchContent,
          Tools::RunCommand
        ].freeze

        def self.builtin_tools
          BUILTIN_TOOLS.dup
        end
      end
    end
  end
end
