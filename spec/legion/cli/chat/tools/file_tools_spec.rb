# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/tools/read_file'
require 'legion/cli/chat/tools/write_file'
require 'legion/cli/chat/tools/edit_file'
require 'legion/cli/chat/tools/search_files'
require 'legion/cli/chat/tools/search_content'

RSpec.describe 'Chat File Tools' do
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
      expect(result).to include('error' .downcase).or include('Error')
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
