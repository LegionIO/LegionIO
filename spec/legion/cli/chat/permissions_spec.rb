# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/tool_registry'

RSpec.describe Legion::CLI::Chat::Permissions do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
    described_class.mode = :interactive
  end

  describe '.tier_for' do
    it 'classifies read tools as :read' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::ReadFile)).to eq(:read)
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::SearchFiles)).to eq(:read)
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::SearchContent)).to eq(:read)
    end

    it 'classifies write tools as :write' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::WriteFile)).to eq(:write)
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::EditFile)).to eq(:write)
    end

    it 'classifies shell tools as :shell' do
      expect(described_class.tier_for(Legion::CLI::Chat::Tools::RunCommand)).to eq(:shell)
    end

    it 'defaults unknown classes to :read' do
      expect(described_class.tier_for(String)).to eq(:read)
    end
  end

  describe '.auto_allow?' do
    it 'returns false in interactive mode' do
      described_class.mode = :interactive
      expect(described_class.auto_allow?).to be false
    end

    it 'returns true in headless mode' do
      described_class.mode = :headless
      expect(described_class.auto_allow?).to be true
    end

    it 'returns true in auto_approve mode' do
      described_class.mode = :auto_approve
      expect(described_class.auto_allow?).to be true
    end
  end

  describe 'Gate module on WriteFile' do
    let(:path) { File.join(tmpdir, 'gated.txt') }

    it 'auto-allows in headless mode' do
      described_class.mode = :headless
      result = Legion::CLI::Chat::Tools::WriteFile.call(path: path, content: 'hello')
      expect(File.read(path)).to eq('hello')
      expect(result).to include('Wrote')
    end

    it 'auto-allows in auto_approve mode' do
      described_class.mode = :auto_approve
      result = Legion::CLI::Chat::Tools::WriteFile.call(path: path, content: 'hello')
      expect(File.read(path)).to eq('hello')
      expect(result).to include('Wrote')
    end

    it 'prompts and allows when user says yes' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("y\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::WriteFile.call(path: path, content: 'hello')
      expect(File.read(path)).to eq('hello')
      expect(result).to include('Wrote')
    end

    it 'prompts and blocks when user says no' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("n\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::WriteFile.call(path: path, content: 'hello')
      expect(result).to eq({ content: [{ type: 'text', text: '{"error":"Tool execution denied by user."}' }], error: true })
      expect(File.exist?(path)).to be false
    end

    it 'includes path in the confirmation prompt' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("y\n")

      expect($stderr).to receive(:print).with(a_string_including(path))
      Legion::CLI::Chat::Tools::WriteFile.call(path: path, content: 'hello')
    end
  end

  describe 'Gate module on EditFile' do
    let(:path) { File.join(tmpdir, 'edit_gated.txt') }

    before { File.write(path, 'hello world') }

    it 'blocks when user denies' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("n\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::EditFile.call(path: path, old_text: 'world', new_text: 'legion')
      expect(result).to eq({ content: [{ type: 'text', text: '{"error":"Tool execution denied by user."}' }], error: true })
      expect(File.read(path)).to eq('hello world')
    end

    it 'allows when user approves' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("yes\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::EditFile.call(path: path, old_text: 'world', new_text: 'legion')
      expect(result).to include('Replaced')
      expect(File.read(path)).to eq('hello legion')
    end
  end

  describe 'Gate module on RunCommand' do
    it 'blocks when user denies' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("n\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::RunCommand.call(command: 'echo hello')
      expect(result).to eq({ content: [{ type: 'text', text: '{"error":"Tool execution denied by user."}' }], error: true })
    end

    it 'allows when user approves' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("y\n")
      allow($stderr).to receive(:print)

      result = Legion::CLI::Chat::Tools::RunCommand.call(command: 'echo hello')
      expect(result).to include('hello')
    end

    it 'includes command in the confirmation prompt' do
      described_class.mode = :interactive
      allow($stdin).to receive(:gets).and_return("y\n")

      expect($stderr).to receive(:print).with(a_string_including('echo hello'))
      Legion::CLI::Chat::Tools::RunCommand.call(command: 'echo hello')
    end
  end

  describe 'ReadFile is NOT gated' do
    it 'executes without prompting in interactive mode' do
      described_class.mode = :interactive
      path = File.join(tmpdir, 'readable.txt')
      File.write(path, 'content here')

      expect($stdin).not_to receive(:gets)
      result = Legion::CLI::Chat::Tools::ReadFile.call(path: path)
      expect(result).to include('content here')
    end
  end

  describe 'SearchFiles is NOT gated' do
    it 'executes without prompting in interactive mode' do
      described_class.mode = :interactive
      File.write(File.join(tmpdir, 'findme.rb'), '')

      expect($stdin).not_to receive(:gets)
      result = Legion::CLI::Chat::Tools::SearchFiles.call(pattern: '*.rb', directory: tmpdir)
      expect(result).to include('findme.rb')
    end
  end
end
