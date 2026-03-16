# frozen_string_literal: true

require 'spec_helper'

begin
  require 'ruby_llm'
rescue LoadError
  # ruby_llm not available — skip these specs
end

require 'legion/cli/chat/tool_registry'

RSpec.describe Legion::CLI::Chat::ToolRegistry, skip: !defined?(RubyLLM) && 'requires ruby_llm' do
  describe '.builtin_tools' do
    it 'returns an array of RubyLLM::Tool subclasses' do
      tools = described_class.builtin_tools
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
      tools.each do |tool|
        expect(tool).to be < RubyLLM::Tool
      end
    end

    it 'includes file and shell tools' do
      names = described_class.builtin_tools.map { |t| t.new.name }
      expect(names.any? { |n| n.end_with?('read_file') }).to be true
      expect(names.any? { |n| n.end_with?('write_file') }).to be true
      expect(names.any? { |n| n.end_with?('edit_file') }).to be true
      expect(names.any? { |n| n.end_with?('search_files') }).to be true
      expect(names.any? { |n| n.end_with?('search_content') }).to be true
      expect(names.any? { |n| n.end_with?('run_command') }).to be true
    end

    it 'returns a mutable copy of the constants array' do
      tools1 = described_class.builtin_tools
      tools2 = described_class.builtin_tools
      expect(tools1).not_to be(tools2)
      expect(tools1).to eq(tools2)
    end
  end
end
