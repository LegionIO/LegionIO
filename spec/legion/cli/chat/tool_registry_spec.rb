# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tool_registry'

RSpec.describe Legion::CLI::Chat::ToolRegistry do
  describe '.builtin_tools' do
    it 'returns an array of Legion::Tools::Base subclasses' do
      tools = described_class.builtin_tools
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
      tools.each do |tool|
        expect(tool).to be < Legion::Tools::Base
      end
    end

    it 'includes file and shell tools' do
      names = described_class.builtin_tools.map(&:tool_name)
      expect(names).to include('legion.read_file')
      expect(names).to include('legion.write_file')
      expect(names).to include('legion.edit_file')
      expect(names).to include('legion.search_files')
      expect(names).to include('legion.search_content')
      expect(names).to include('legion.run_command')
    end

    it 'returns a mutable copy of the constants array' do
      tools1 = described_class.builtin_tools
      tools2 = described_class.builtin_tools
      expect(tools1).not_to be(tools2)
      expect(tools1).to eq(tools2)
    end
  end

  # Regression guard for the `ask` / `chat prompt` client path.
  #
  # The chat tool files (Tools::ReadFile, etc.) subclass Legion::Tools::Base,
  # but only legion.rb and legion/service.rb require 'legion/tools'. The CLI
  # client path loads neither, so requiring this registry used to raise
  # `uninitialized constant Legion::Tools`. tool_registry.rb must therefore
  # pull in legion/tools itself.
  #
  # The spec suite loads the full `legion` entrypoint via spec_helper, which
  # requires legion/tools as a side effect, so an in-process constant check
  # cannot reproduce the failure. We assert the source-level contract instead:
  # the registry must declare the require so the constant is satisfied on the
  # client path where spec_helper's eager load is absent.
  describe 'self-sufficiency on the CLI client path' do
    let(:source) do
      path = File.expand_path('../../../../lib/legion/cli/chat/tool_registry.rb', __dir__)
      File.read(path)
    end

    it "requires 'legion/tools' before the chat tool files" do
      tools_require   = source.index(%r{^\s*require ['"]legion/tools['"]})
      first_tool_file = source.index(%r{^\s*require ['"]legion/cli/chat/tools/})

      # nil here means the require is missing — Legion::Tools::Base would be
      # undefined on the client path and requiring the registry would raise.
      expect(tools_require).not_to be_nil
      expect(tools_require).to be < first_tool_file
    end

    it 'resolves Legion::Tools::Base as the superclass of every builtin tool' do
      expect(defined?(Legion::Tools::Base)).to eq('constant')
      described_class.builtin_tools.each do |tool|
        expect(tool.ancestors).to include(Legion::Tools::Base)
      end
    end
  end
end
