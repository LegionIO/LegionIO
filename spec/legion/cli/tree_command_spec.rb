# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe Legion::CLI::Main do
  def capture_tree_output
    output = StringIO.new
    instance = described_class.new([], json: false, no_color: true, verbose: false)
    allow(instance).to receive(:say) do |text, _color = nil, _newline = true|
      output.print(text.to_s)
    end
    instance.tree
    output.string
  end

  describe '#tree' do
    subject(:output) { capture_tree_output }

    let(:prog) { File.basename($PROGRAM_NAME) }

    it 'shows the binary name as the root node' do
      expect(output).to include(prog)
    end

    it 'does not expose internal Thor namespace paths' do
      expect(output).not_to include('c_l_i')
    end

    it 'does not show the raw namespace for the root command' do
      expect(output).not_to include("#{prog}:c_l_i:main")
    end

    it 'shows subcommand groups with clean prefixed names' do
      expect(output).to include("#{prog} lex")
      expect(output).to include("#{prog} task")
      expect(output).to include("#{prog} worker")
    end

    it 'does not show raw namespace for subcommands' do
      expect(output).not_to include("#{prog}:c_l_i:lex")
      expect(output).not_to include("#{prog}:c_l_i:task")
    end

    it 'includes top-level commands like version and start' do
      expect(output).to include('version')
      expect(output).to include('start')
    end

    it 'does not include tree itself in the output' do
      # tree should suppress itself to avoid noise
      lines = output.split("\n").map(&:strip)
      command_lines = lines.grep(/^[├└]/)
      expect(command_lines.none? { |l| l.include?('tree') }).to be true
    end
  end
end
