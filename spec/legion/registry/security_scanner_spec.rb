# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'legion/registry/security_scanner'

RSpec.describe Legion::Registry::SecurityScanner do
  let(:scanner) { described_class.new }

  describe '#scan' do
    it 'returns result hash' do
      result = scanner.scan(name: 'lex-test')
      expect(result).to have_key(:passed)
      expect(result).to have_key(:checks)
      expect(result).to have_key(:scanned_at)
    end

    it 'passes valid naming' do
      result = scanner.scan(name: 'lex-test')
      naming = result[:checks].find { |c| c[:check] == :naming_convention }
      expect(naming[:status]).to eq(:pass)
    end

    it 'fails invalid naming' do
      result = scanner.scan(name: 'bad_name')
      naming = result[:checks].find { |c| c[:check] == :naming_convention }
      expect(naming[:status]).to eq(:fail)
    end

    it 'skips checksum without gem path' do
      result = scanner.scan(name: 'lex-test')
      checksum = result[:checks].find { |c| c[:check] == :checksum }
      expect(checksum[:status]).to eq(:skip)
    end

    it 'overall passes when no failures' do
      result = scanner.scan(name: 'lex-test')
      expect(result[:passed]).to be true
    end

    it 'overall fails when naming fails' do
      result = scanner.scan(name: 'BAD')
      expect(result[:passed]).to be false
    end

    it 'skips static_analysis when no source_path provided' do
      result = scanner.scan(name: 'lex-test')
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:skip)
      expect(sa[:details]).to eq('no source path')
    end

    it 'overall still passes when static_analysis is :warn' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'bad.rb'), "IO.popen('dangerous_cmd')\n")
        result = scanner.scan(name: 'lex-test', source_path: dir)
        sa = result[:checks].find { |c| c[:check] == :static_analysis }
        expect(sa[:status]).to eq(:warn)
        expect(result[:passed]).to be true
      end
    end
  end

  describe '#static_analysis' do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmpdir) }

    def write_rb(name, content)
      File.write(File.join(tmpdir, name), content)
    end

    it 'passes for clean Ruby source' do
      write_rb('clean.rb', "def hello\n  'world'\nend\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:pass)
      expect(sa[:details]).to eq('no dangerous patterns found')
    end

    it 'warns for system call usage' do
      write_rb('sys.rb', "Kernel.system('rm -rf /')\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('system')
    end

    it 'warns for IO.popen usage' do
      write_rb('io.rb', "IO.popen('cmd') { |f| f.read }\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('IO.popen')
    end

    it 'warns for Open3 usage' do
      write_rb('open3.rb', "require 'open3'\nOpen3.capture3('cmd')\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('Open3')
    end

    it 'warns for eval usage' do
      write_rb('evil.rb', "eval(user_input)\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('eval')
    end

    it 'warns for backtick subshell' do
      write_rb('shell.rb', "output = `ls -la`\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('backtick subshell')
    end

    it 'scans only .rb files and ignores other extensions' do
      write_rb('notes.md', "Use backtick for shell commands\n")
      write_rb('clean.rb', "puts 'hello'\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:pass)
    end

    it 'includes relative path and line number in findings' do
      write_rb('runner.rb', "# line 1\nIO.popen('cmd')\n")
      result = scanner.scan(source_path: tmpdir)
      sa = result[:checks].find { |c| c[:check] == :static_analysis }
      expect(sa[:status]).to eq(:warn)
      expect(sa[:details]).to include('runner.rb:2')
    end
  end
end
