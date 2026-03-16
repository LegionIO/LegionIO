# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

begin
  require 'ruby_llm'
  require 'legion/cli/chat/tools/read_file'
  require 'legion/cli/chat/tools/write_file'
  require 'legion/cli/chat/tools/edit_file'
  require 'legion/cli/chat/tools/search_files'
  require 'legion/cli/chat/tools/search_content'
rescue LoadError
  # ruby_llm not available
end

RSpec.describe 'Chat File Tools', skip: !defined?(RubyLLM) && 'requires ruby_llm' do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe Legion::CLI::Chat::Tools::ReadFile do
    let(:tool) { described_class.new }

    it 'reads file contents' do
      path = File.join(tmpdir, 'test.txt')
      File.write(path, "line1\nline2\nline3")
      result = tool.execute(path: path)
      expect(result).to include('line1')
      expect(result).to include('line3')
    end

    it 'returns error for missing file' do
      result = tool.execute(path: '/nonexistent/file.txt')
      expect(result).to include('error'.downcase).or include('Error')
    end

    it 'supports offset and limit' do
      path = File.join(tmpdir, 'test.txt')
      File.write(path, "line1\nline2\nline3\nline4\nline5")
      result = tool.execute(path: path, offset: 2, limit: 2)
      expect(result).to include('line2')
      expect(result).to include('line3')
      expect(result).not_to include('line4')
    end
  end

  describe Legion::CLI::Chat::Tools::WriteFile do
    let(:tool) { described_class.new }

    it 'creates a new file' do
      path = File.join(tmpdir, 'new.txt')
      result = tool.execute(path: path, content: 'hello world')
      expect(File.read(path)).to eq('hello world')
      expect(result.downcase).to include('wrote')
    end

    it 'creates parent directories' do
      path = File.join(tmpdir, 'sub', 'dir', 'new.txt')
      tool.execute(path: path, content: 'nested')
      expect(File.read(path)).to eq('nested')
    end
  end

  describe Legion::CLI::Chat::Tools::EditFile do
    let(:tool) { described_class.new }

    it 'replaces text in a file' do
      path = File.join(tmpdir, 'edit.txt')
      File.write(path, 'hello world')
      result = tool.execute(path: path, old_text: 'world', new_text: 'legion')
      expect(File.read(path)).to eq('hello legion')
      expect(result.downcase).to include('replaced')
    end

    it 'errors when old_text not found' do
      path = File.join(tmpdir, 'edit.txt')
      File.write(path, 'hello world')
      result = tool.execute(path: path, old_text: 'missing', new_text: 'x')
      expect(result.downcase).to include('error')
    end

    it 'errors when old_text matches multiple times' do
      path = File.join(tmpdir, 'edit.txt')
      File.write(path, 'aaa bbb aaa')
      result = tool.execute(path: path, old_text: 'aaa', new_text: 'x')
      expect(result.downcase).to include('error')
    end

    it 'errors when no old_text and no start_line provided' do
      path = File.join(tmpdir, 'edit.txt')
      File.write(path, "line1\nline2\n")
      result = tool.execute(path: path, new_text: 'x')
      expect(result.downcase).to include('error')
    end

    context 'line-number mode' do
      it 'replaces a single line when only start_line is given' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        result = tool.execute(path: path, new_text: 'replaced', start_line: 2)
        expect(File.read(path)).to eq("line1\nreplaced\nline3\n")
        expect(result.downcase).to include('replaced')
      end

      it 'replaces a range of lines when start_line and end_line are given' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\nline4\n")
        result = tool.execute(path: path, new_text: 'new', start_line: 2, end_line: 3)
        expect(File.read(path)).to eq("line1\nnew\nline4\n")
        expect(result.downcase).to include('replaced')
      end

      it 'replaces the first line' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        tool.execute(path: path, new_text: 'first', start_line: 1)
        expect(File.read(path)).to eq("first\nline2\nline3\n")
      end

      it 'replaces the last line' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        tool.execute(path: path, new_text: 'last', start_line: 3)
        expect(File.read(path)).to eq("line1\nline2\nlast\n")
      end

      it 'preserves trailing newline when replacement text already has one' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        tool.execute(path: path, new_text: "newline\n", start_line: 2)
        expect(File.read(path)).to eq("line1\nnewline\nline3\n")
      end

      it 'ignores old_text when start_line is provided' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        result = tool.execute(path: path, new_text: 'x', old_text: 'nomatch', start_line: 1)
        expect(result.downcase).not_to include('error')
        expect(File.read(path)).to include('x')
      end

      it 'errors when start_line is out of bounds' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\n")
        result = tool.execute(path: path, new_text: 'x', start_line: 10)
        expect(result.downcase).to include('error')
      end

      it 'errors when end_line is out of bounds' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\n")
        result = tool.execute(path: path, new_text: 'x', start_line: 1, end_line: 99)
        expect(result.downcase).to include('error')
      end

      it 'errors when end_line is before start_line' do
        path = File.join(tmpdir, 'lines.txt')
        File.write(path, "line1\nline2\nline3\n")
        result = tool.execute(path: path, new_text: 'x', start_line: 3, end_line: 1)
        expect(result.downcase).to include('error')
      end
    end
  end

  describe Legion::CLI::Chat::Tools::SearchFiles do
    let(:tool) { described_class.new }

    it 'finds files matching a glob pattern' do
      File.write(File.join(tmpdir, 'foo.rb'), '')
      File.write(File.join(tmpdir, 'bar.rb'), '')
      File.write(File.join(tmpdir, 'baz.txt'), '')
      result = tool.execute(pattern: '*.rb', directory: tmpdir)
      expect(result).to include('foo.rb')
      expect(result).to include('bar.rb')
      expect(result).not_to include('baz.txt')
    end
  end

  describe Legion::CLI::Chat::Tools::SearchContent do
    let(:tool) { described_class.new }

    it 'finds files containing a pattern' do
      File.write(File.join(tmpdir, 'match.rb'), 'def hello; end')
      File.write(File.join(tmpdir, 'nomatch.rb'), 'x = 1')
      result = tool.execute(pattern: 'def hello', directory: tmpdir)
      expect(result).to include('match.rb')
    end
  end
end
