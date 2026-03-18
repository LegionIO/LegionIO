# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'tempfile'
require 'legion/cli/error'
require 'legion/cli/config_import'

RSpec.describe Legion::CLI::ConfigImport do
  describe '.parse_payload' do
    context 'with raw JSON' do
      it 'parses a valid JSON object' do
        body = '{"transport":{"host":"localhost"}}'
        result = described_class.parse_payload(body)
        expect(result).to eq({ transport: { host: 'localhost' } })
      end

      it 'raises CLI::Error for a JSON array' do
        body = '[1, 2, 3]'
        expect { described_class.parse_payload(body) }
          .to raise_error(Legion::CLI::Error, 'Config must be a JSON object')
      end
    end

    context 'with base64-encoded JSON' do
      it 'parses base64-encoded JSON object' do
        payload = Base64.encode64('{"data":{"adapter":"sqlite"}}')
        result = described_class.parse_payload(payload)
        expect(result).to eq({ data: { adapter: 'sqlite' } })
      end

      it 'raises CLI::Error for base64-encoded non-object JSON' do
        payload = Base64.encode64('[1, 2, 3]')
        expect { described_class.parse_payload(payload) }
          .to raise_error(Legion::CLI::Error, 'Config must be a JSON object')
      end
    end

    context 'with invalid input' do
      it 'raises CLI::Error when input is neither JSON nor base64 JSON' do
        expect { described_class.parse_payload('not valid at all!!!') }
          .to raise_error(Legion::CLI::Error, 'Source is not valid JSON or base64-encoded JSON')
      end
    end
  end

  describe '.fetch_source' do
    context 'with a local file' do
      it 'reads the file contents' do
        Tempfile.create(['legion-import', '.json']) do |f|
          f.write('{"logging":{"level":"info"}}')
          f.flush
          result = described_class.fetch_source(f.path)
          expect(result).to eq('{"logging":{"level":"info"}}')
        end
      end

      it 'raises CLI::Error when the file does not exist' do
        expect { described_class.fetch_source('/tmp/does_not_exist_legion_test.json') }
          .to raise_error(Legion::CLI::Error, /File not found/)
      end
    end

    context 'with an HTTP URL' do
      it 'delegates to fetch_http' do
        allow(described_class).to receive(:fetch_http).with('http://example.com/config.json').and_return('{}')
        result = described_class.fetch_source('http://example.com/config.json')
        expect(result).to eq('{}')
      end

      it 'delegates to fetch_http for https URLs' do
        allow(described_class).to receive(:fetch_http).with('https://example.com/config.json').and_return('{}')
        result = described_class.fetch_source('https://example.com/config.json')
        expect(result).to eq('{}')
      end
    end
  end

  describe '.summary' do
    it 'returns top-level section names' do
      config = { transport: { host: 'localhost' }, data: { adapter: 'sqlite' } }
      result = described_class.summary(config)
      expect(result[:sections]).to contain_exactly('transport', 'data')
    end

    it 'returns empty vault_clusters when no crypt key present' do
      config = { transport: { host: 'localhost' } }
      result = described_class.summary(config)
      expect(result[:vault_clusters]).to eq([])
    end

    it 'returns vault cluster names when present' do
      config = {
        crypt: {
          vault: {
            clusters: {
              primary:   { address: 'https://vault.example.com' },
              secondary: { address: 'https://vault2.example.com' }
            }
          }
        }
      }
      result = described_class.summary(config)
      expect(result[:vault_clusters]).to contain_exactly('primary', 'secondary')
    end
  end

  describe '.write_config' do
    let(:tmpdir) { Dir.mktmpdir('legion-import-spec') }

    before do
      stub_const('Legion::CLI::ConfigImport::SETTINGS_DIR', tmpdir)
    end

    after { FileUtils.rm_rf(tmpdir) }

    it 'writes config JSON to disk' do
      config = { transport: { host: 'localhost' } }
      path = described_class.write_config(config)
      expect(File.exist?(path)).to be(true)
      written = JSON.parse(File.read(path), symbolize_names: true)
      expect(written[:transport][:host]).to eq('localhost')
    end

    it 'returns the full path to the written file' do
      config = { logging: { level: 'info' } }
      path = described_class.write_config(config)
      expect(path).to eq(File.join(tmpdir, 'imported.json'))
    end

    it 'deep merges with existing file when force is false' do
      existing = { transport: { host: 'old-host', port: 5672 } }
      File.write(File.join(tmpdir, 'imported.json'), JSON.generate(existing))

      overlay = { transport: { host: 'new-host' }, data: { adapter: 'sqlite' } }
      described_class.write_config(overlay, force: false)

      result = JSON.parse(File.read(File.join(tmpdir, 'imported.json')), symbolize_names: true)
      expect(result[:transport][:host]).to eq('new-host')
      expect(result[:transport][:port]).to eq(5672)
      expect(result[:data][:adapter]).to eq('sqlite')
    end

    it 'overwrites existing file with force: true' do
      existing = { transport: { host: 'old-host', port: 5672 } }
      File.write(File.join(tmpdir, 'imported.json'), JSON.generate(existing))

      new_config = { logging: { level: 'debug' } }
      described_class.write_config(new_config, force: true)

      result = JSON.parse(File.read(File.join(tmpdir, 'imported.json')), symbolize_names: true)
      expect(result.keys).to eq([:logging])
      expect(result[:logging][:level]).to eq('debug')
    end

    it 'creates the settings directory if it does not exist' do
      nested = File.join(tmpdir, 'nested', 'settings')
      stub_const('Legion::CLI::ConfigImport::SETTINGS_DIR', nested)
      described_class.write_config({ logging: { level: 'info' } })
      expect(Dir.exist?(nested)).to be(true)
    end
  end

  describe '.deep_merge' do
    it 'merges nested hashes recursively' do
      base    = { a: { x: 1, y: 2 }, b: 'keep' }
      overlay = { a: { y: 99, z: 3 }, c: 'new' }
      result  = described_class.deep_merge(base, overlay)
      expect(result).to eq({ a: { x: 1, y: 99, z: 3 }, b: 'keep', c: 'new' })
    end

    it 'overwrites non-hash values with overlay' do
      base    = { a: [1, 2, 3] }
      overlay = { a: [4, 5] }
      result  = described_class.deep_merge(base, overlay)
      expect(result[:a]).to eq([4, 5])
    end
  end
end
