# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'

RSpec.describe 'Chat headless mode' do
  it 'prompt command accepts text argument' do
    chat = Legion::CLI::Chat.new
    expect(chat).to respond_to(:prompt)
  end

  it 'has prompt command registered' do
    expect(Legion::CLI::Chat.all_commands).to have_key('prompt')
  end

  it 'Main has ask command mapped to -p' do
    expect(Legion::CLI::Main.instance_methods).to include(:ask)
  end

  describe 'combine_with_stdin' do
    let(:chat) { Legion::CLI::Chat.new }

    it 'returns text unchanged when stdin is a TTY' do
      allow($stdin).to receive(:tty?).and_return(true)
      result = chat.send(:combine_with_stdin, 'hello')
      expect(result).to eq('hello')
    end

    it 'reads piped stdin when text is empty' do
      allow($stdin).to receive(:tty?).and_return(false)
      allow($stdin).to receive(:read).and_return("piped content\n")
      result = chat.send(:combine_with_stdin, '')
      expect(result).to eq('piped content')
    end

    it 'combines text and piped stdin' do
      allow($stdin).to receive(:tty?).and_return(false)
      allow($stdin).to receive(:read).and_return("file contents\n")
      result = chat.send(:combine_with_stdin, 'review this')
      expect(result).to eq("review this\n\nfile contents\n")
    end
  end

  describe 'exe/legion pipe routing' do
    it 'routes to chat prompt when stdin is piped with no args' do
      content = File.read(File.expand_path('../../../../exe/legion', __dir__))
      expect(content).to include("ARGV.replace(['chat', 'prompt', ''])")
    end
  end
end
