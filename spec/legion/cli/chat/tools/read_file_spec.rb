  describe 'output truncation' do
    it 'truncates long content at MAX_OUTPUT_CHARS' do
      path = File.join(tmpdir, 'large.txt')
      large_content = 'x' * 50_000  # Exceeds 48K limit
      File.write(path, large_content)

      result = tool.execute(path: path)

      expect(result).to include('truncated at 48000 characters')
      expect(result).to include('use offset/limit params')
      expect(result.length).to be < large_content.length
    end

    it 'respects settings-based max_output_chars override' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :tools, :max_output_chars).and_return(100)

      path = File.join(tmpdir, 'medium.txt')
      File.write(path, 'x' * 200)

      result = tool.execute(path: path)

      expect(result).to include('truncated at 100 characters')
    end

    it 'does not truncate short content' do
      path = File.join(tmpdir, 'small.txt')
      File.write(path, "line 1\nline 2\nline 3")

      result = tool.execute(path: path)

      expect(result).not_to include('truncated')
      expect(result).to include('small.txt (3 lines total)')
      expect(result).to include('1 | line 1')
    end
  end