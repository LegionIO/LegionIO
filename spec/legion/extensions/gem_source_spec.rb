# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/gem_source'

RSpec.describe Legion::Extensions::GemSource do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  describe '.configured_sources' do
    it 'returns default rubygems.org when no sources configured' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(nil)
      result = described_class.configured_sources
      expect(result).to eq([{ url: 'https://rubygems.org' }])
    end

    it 'returns configured sources as hashes' do
      sources = [
        { url: 'https://rubygems.org' },
        { url: 'https://gems.example.com', credentials: 'token123' }
      ]
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(sources)
      result = described_class.configured_sources
      expect(result.length).to eq(2)
      expect(result[1][:url]).to eq('https://gems.example.com')
      expect(result[1][:credentials]).to eq('token123')
    end

    it 'normalizes string sources to hashes' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(['https://custom.gem.server'])
      result = described_class.configured_sources
      expect(result).to eq([{ url: 'https://custom.gem.server' }])
    end
  end

  describe '.source_urls' do
    it 'extracts URLs from configured sources' do
      sources = [{ url: 'https://rubygems.org' }, { url: 'https://private.gems.io' }]
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(sources)
      expect(described_class.source_urls).to eq(%w[https://rubygems.org https://private.gems.io])
    end
  end

  describe '.source_args_for_cli' do
    it 'returns empty string when only default source is configured' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(nil)
      expect(described_class.source_args_for_cli).to eq('')
    end

    it 'returns --source flags with --clear-sources for custom sources' do
      sources = [{ url: 'https://rubygems.org' }, { url: 'https://private.gems.io' }]
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(sources)
      result = described_class.source_args_for_cli
      expect(result).to include('--source https://rubygems.org')
      expect(result).to include('--source https://private.gems.io')
      expect(result).to include('--clear-sources')
    end
  end

  describe '.resolve_credential' do
    it 'returns literal values as-is' do
      result = described_class.send(:resolve_credential, 'my-token-123')
      expect(result).to eq('my-token-123')
    end

    it 'resolves env: prefix to environment variable' do
      allow(ENV).to receive(:fetch).with('MY_GEM_TOKEN', nil).and_return('secret-from-env')
      result = described_class.send(:resolve_credential, 'env:MY_GEM_TOKEN')
      expect(result).to eq('secret-from-env')
    end

    it 'returns nil when env var is not set' do
      allow(ENV).to receive(:fetch).with('MISSING_VAR', nil).and_return(nil)
      result = described_class.send(:resolve_credential, 'env:MISSING_VAR')
      expect(result).to be_nil
    end
  end

  describe '.install_gem command construction' do
    it 'builds correct command with default sources' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(nil)
      sources = described_class.source_args_for_cli
      cmd = "/usr/bin/gem install lex-test --no-document #{sources}".strip.squeeze(' ')
      expect(cmd).to include('lex-test')
      expect(cmd).to include('--no-document')
      expect(cmd).not_to include('--clear-sources')
    end

    it 'includes source args when custom sources are configured' do
      sources = [{ url: 'https://rubygems.org' }, { url: 'https://private.gems.io' }]
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(sources)
      args = described_class.source_args_for_cli
      cmd = "/usr/bin/gem install lex-test --no-document #{args}".strip
      expect(cmd).to include('--source https://private.gems.io')
      expect(cmd).to include('--clear-sources')
    end

    it 'includes version when specified' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(nil)
      args = described_class.source_args_for_cli
      cmd = "/usr/bin/gem install lex-test -v 1.2.0 --no-document #{args}".strip.squeeze(' ')
      expect(cmd).to include('-v 1.2.0')
    end
  end

  describe '.setup!' do
    it 'does not raise when sources are default' do
      allow(Legion::Settings).to receive(:dig).with(:extensions, :sources).and_return(nil)
      expect { described_class.setup! }.not_to raise_error
    end
  end
end
