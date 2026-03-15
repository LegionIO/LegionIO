# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/markdown_renderer'

RSpec.describe Legion::CLI::Chat::MarkdownRenderer do
  describe '.render' do
    it 'returns text unchanged when color is false' do
      result = described_class.render("# Hello\n**bold**", color: false)
      expect(result).to eq("# Hello\n**bold**")
    end

    it 'renders h1 headers with bold and color' do
      result = described_class.render("# Title\n", color: true)
      expect(result).to include('Title')
      expect(result).to include("\e[1m")
    end

    it 'renders h2 headers' do
      result = described_class.render("## Subtitle\n", color: true)
      expect(result).to include('Subtitle')
      expect(result).to include("\e[1m")
    end

    it 'renders h3+ headers' do
      result = described_class.render("### Section\n", color: true)
      expect(result).to include('Section')
      expect(result).to include("\e[1m")
    end

    it 'renders bold text' do
      result = described_class.render("this is **bold** text\n", color: true)
      expect(result).to include("\e[1m")
      expect(result).to include('bold')
    end

    it 'renders italic text' do
      result = described_class.render("this is *italic* text\n", color: true)
      expect(result).to include("\e[3m")
      expect(result).to include('italic')
    end

    it 'renders inline code' do
      result = described_class.render("use `foo` here\n", color: true)
      expect(result).to include('foo')
      expect(result).to include("\e[48;5;236m")
    end

    it 'renders horizontal rules' do
      result = described_class.render("---\n", color: true)
      expect(result).to include("\e[2m")
    end

    it 'renders blockquotes' do
      result = described_class.render("> quoted text\n", color: true)
      expect(result).to include('quoted text')
      expect(result).to include("\e[2m")
    end

    it 'renders unordered list items' do
      result = described_class.render("- item one\n- item two\n", color: true)
      expect(result).to include('item one')
      expect(result).to include('item two')
    end

    it 'renders ordered list items' do
      result = described_class.render("1. first\n2. second\n", color: true)
      expect(result).to include('first')
      expect(result).to include('second')
    end

    context 'with code blocks' do
      it 'highlights a ruby code block' do
        input = "```ruby\ndef hello\n  puts 'hi'\nend\n```\n"
        result = described_class.render(input, color: true)
        expect(result).to include('def')
        expect(result).to include('hello')
        expect(result).to include("\e[") # contains ANSI escape codes
      end

      it 'shows language label' do
        input = "```python\nprint('hi')\n```\n"
        result = described_class.render(input, color: true)
        expect(result).to include('python')
      end

      it 'handles code blocks without language' do
        input = "```\nsome code\n```\n"
        result = described_class.render(input, color: true)
        expect(result).to include('some code')
      end

      it 'handles unclosed code blocks gracefully' do
        input = "```ruby\ndef oops\n"
        result = described_class.render(input, color: true)
        expect(result).to include('def')
      end
    end

    context 'with mixed content' do
      it 'renders text before and after code blocks' do
        input = "Here is code:\n\n```ruby\nx = 1\n```\n\nDone.\n"
        result = described_class.render(input, color: true)
        expect(result).to include('Here is code:')
        expect(result).to include('Done.')
      end

      it 'renders multiple code blocks' do
        input = "```ruby\na = 1\n```\n\nThen:\n\n```python\nb = 2\n```\n"
        result = described_class.render(input, color: true)
        expect(result).to include('ruby')
        expect(result).to include('python')
      end
    end
  end
end
