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
end
