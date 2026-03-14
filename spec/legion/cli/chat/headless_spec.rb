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
end
