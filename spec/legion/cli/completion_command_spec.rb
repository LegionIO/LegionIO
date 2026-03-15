# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/completion_command'
require 'legion/cli/output'

RSpec.describe Legion::CLI::Completion do
  it 'is a Thor subclass' do
    expect(described_class.ancestors).to include(Thor)
  end

  it 'responds to bash' do
    expect(described_class.instance_methods).to include(:bash)
  end

  it 'responds to zsh' do
    expect(described_class.instance_methods).to include(:zsh)
  end

  it 'responds to install' do
    expect(described_class.instance_methods).to include(:install)
  end

  describe 'COMPLETION_DIR' do
    it 'points to the completions directory' do
      expect(described_class::COMPLETION_DIR).to end_with('completions')
    end

    it 'the completions directory exists' do
      expect(Dir.exist?(described_class::COMPLETION_DIR)).to be true
    end
  end

  describe '#bash' do
    it 'outputs the bash completion script' do
      output = StringIO.new
      instance = described_class.new
      allow(instance).to receive(:puts) { |text| output.puts(text) }
      instance.bash
      expect(output.string).to include('_legion_complete')
      expect(output.string).to include('complete -F _legion_complete legion')
    end
  end

  describe '#zsh' do
    it 'outputs the zsh completion script' do
      output = StringIO.new
      instance = described_class.new
      allow(instance).to receive(:puts) { |text| output.puts(text) }
      instance.zsh
      expect(output.string).to include('#compdef legion')
      expect(output.string).to include('_legion_commands')
    end
  end

  describe 'completion files' do
    it 'bash completion file exists' do
      path = File.join(described_class::COMPLETION_DIR, 'legion.bash')
      expect(File.exist?(path)).to be true
    end

    it 'zsh completion file exists' do
      path = File.join(described_class::COMPLETION_DIR, '_legion')
      expect(File.exist?(path)).to be true
    end

    it 'bash completion file contains top-level commands' do
      path = File.join(described_class::COMPLETION_DIR, 'legion.bash')
      content = File.read(path)
      %w[start stop status check lex task chain config generate mcp worker
         coldstart chat memory plan swarm commit pr review gaia schedule completion].each do |cmd|
        expect(content).to include(cmd)
      end
    end

    it 'zsh completion file contains top-level commands' do
      path = File.join(described_class::COMPLETION_DIR, '_legion')
      content = File.read(path)
      %w[start stop status check lex task chain config generate mcp worker
         coldstart chat memory plan swarm commit pr review gaia schedule completion].each do |cmd|
        expect(content).to include(cmd)
      end
    end
  end
end
