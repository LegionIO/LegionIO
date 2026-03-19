# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Permissions do
  before { described_class.reset! }

  describe '.sandbox_path' do
    it 'returns the default sandbox for an extension' do
      path = described_class.sandbox_path('lex-github')
      expect(path).to eq(File.expand_path('~/.legionio/data/lex-github'))
    end
  end

  describe '.allowed?' do
    it 'always allows sandbox paths' do
      path = File.expand_path('~/.legionio/data/lex-github/cache.json')
      expect(described_class.allowed?('lex-github', path, :read)).to be true
    end

    it 'denies paths outside sandbox by default' do
      expect(described_class.allowed?('lex-github', '/etc/passwd', :read)).to be false
    end

    it 'allows paths matching auto-approve globs' do
      described_class.add_auto_approve('lex-github', ['/Users/test/repos/**'])
      expect(described_class.allowed?('lex-github', '/Users/test/repos/myapp/README.md', :read)).to be true
    end

    it 'allows explicitly approved paths' do
      described_class.approve('lex-github', '/var/log/github/', :read)
      expect(described_class.allowed?('lex-github', '/var/log/github/app.log', :read)).to be true
    end
  end

  describe '.approve and .deny' do
    it 'stores approval' do
      described_class.approve('lex-github', '/tmp/test/', :write)
      expect(described_class.approved?('lex-github', '/tmp/test/', :write)).to be true
    end

    it 'stores denial' do
      described_class.deny('lex-github', '/tmp/test/', :write)
      expect(described_class.approved?('lex-github', '/tmp/test/', :write)).to be false
    end
  end

  describe '.declared_paths' do
    it 'returns empty arrays for unknown extensions' do
      result = described_class.declared_paths('lex-unknown')
      expect(result).to eq({ read_paths: [], write_paths: [] })
    end
  end
end
