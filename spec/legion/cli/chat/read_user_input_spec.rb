# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli'
require 'reline'

RSpec.describe 'Legion::CLI::Chat#read_user_input' do
  subject(:chat) { Legion::CLI::Chat.new }

  describe '#read_user_input' do
    it 'returns a single line on normal Enter' do
      allow(Reline).to receive(:readline).and_return('hello world')
      expect(chat.read_user_input).to eq('hello world')
    end

    it 'returns nil on Ctrl+D (EOF)' do
      allow(Reline).to receive(:readline).and_return(nil)
      expect(chat.read_user_input).to be_nil
    end

    it 'returns empty string for blank input' do
      allow(Reline).to receive(:readline).and_return('   ')
      expect(chat.read_user_input).to eq('')
    end

    it 'joins continuation lines separated by trailing backslash' do
      allow(Reline).to receive(:readline).and_return(
        'first line\\',
        'second line\\',
        'third line'
      )
      expect(chat.read_user_input).to eq("first line\nsecond line\nthird line")
    end

    it 'strips trailing whitespace before the backslash' do
      allow(Reline).to receive(:readline).and_return(
        'hello   \\',
        'world'
      )
      expect(chat.read_user_input).to eq("hello\nworld")
    end

    it 'only adds the first line to Reline history' do
      call_count = 0
      allow(Reline).to receive(:readline) do |_prompt, add_hist|
        call_count += 1
        case call_count
        when 1
          expect(add_hist).to be true
          'line one\\'
        when 2
          expect(add_hist).to be false
          'line two'
        end
      end

      chat.read_user_input
    end

    it 'shows a continuation prompt for subsequent lines' do
      call_count = 0
      allow(Reline).to receive(:readline) do |prompt, _add_hist|
        call_count += 1
        case call_count
        when 1
          expect(prompt).to include('you')
          'continued\\'
        when 2
          expect(prompt).to include('...')
          'done'
        end
      end

      chat.read_user_input
    end

    it 'handles a single backslash at end of line with no continuation text' do
      allow(Reline).to receive(:readline).and_return('\\', 'actual content')
      expect(chat.read_user_input).to eq("\nactual content")
    end

    it 'returns nil when Ctrl+D during continuation' do
      allow(Reline).to receive(:readline).and_return('start\\', nil)
      expect(chat.read_user_input).to be_nil
    end

    it 're-raises Interrupt on first line' do
      allow(Reline).to receive(:readline).and_raise(Interrupt)
      expect { chat.read_user_input }.to raise_error(Interrupt)
    end

    it 'returns nil on Interrupt during continuation' do
      call_count = 0
      allow(Reline).to receive(:readline) do
        call_count += 1
        case call_count
        when 1 then 'start\\'
        when 2 then raise Interrupt
        end
      end

      expect(chat.read_user_input).to be_nil
    end

    it 'does not treat mid-line backslashes as continuation' do
      allow(Reline).to receive(:readline).and_return('path\\to\\file')
      expect(chat.read_user_input).to eq('path\\to\\file')
    end
  end
end
