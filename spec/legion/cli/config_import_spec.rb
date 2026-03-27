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

    it 'returns an array of written paths' do
      config = { transport: { host: 'localhost' } }
      paths = described_class.write_config(config)
      expect(paths).to be_an(Array)
    end

    it 'writes recognized subsystem keys to individual files' do
      config = { transport: { host: 'localhost' }, llm: { enabled: true } }
      paths = described_class.write_config(config)

      transport_path = File.join(tmpdir, 'transport.json')
      llm_path = File.join(tmpdir, 'llm.json')

      expect(paths).to include(transport_path, llm_path)
      expect(File.exist?(transport_path)).to be(true)
      expect(File.exist?(llm_path)).to be(true)

      transport_data = JSON.parse(File.read(transport_path), symbolize_names: true)
      expect(transport_data).to eq({ transport: { host: 'localhost' } })

      llm_data = JSON.parse(File.read(llm_path), symbolize_names: true)
      expect(llm_data).to eq({ llm: { enabled: true } })
    end

    it 'writes unrecognized keys to bootstrapped_settings.json' do
      config = { custom_thing: { foo: 'bar' }, another: 123 }
      paths = described_class.write_config(config)

      bootstrapped_path = File.join(tmpdir, 'bootstrapped_settings.json')
      expect(paths).to include(bootstrapped_path)

      written = JSON.parse(File.read(bootstrapped_path), symbolize_names: true)
      expect(written).to eq({ custom_thing: { foo: 'bar' }, another: 123 })
    end

    it 'splits a mixed config into subsystem files and remainder' do
      config = { logging: { level: 'debug' }, transport: { host: 'rmq' }, app_name: 'test' }
      paths = described_class.write_config(config)

      expect(paths.size).to eq(3)
      expect(File.exist?(File.join(tmpdir, 'logging.json'))).to be(true)
      expect(File.exist?(File.join(tmpdir, 'transport.json'))).to be(true)
      expect(File.exist?(File.join(tmpdir, 'bootstrapped_settings.json'))).to be(true)

      remainder = JSON.parse(File.read(File.join(tmpdir, 'bootstrapped_settings.json')), symbolize_names: true)
      expect(remainder).to eq({ app_name: 'test' })
    end

    it 'does not write bootstrapped_settings.json when all keys are subsystem keys' do
      config = { logging: { level: 'info' }, cache: { driver: 'dalli' } }
      paths = described_class.write_config(config)

      expect(paths).not_to include(File.join(tmpdir, 'bootstrapped_settings.json'))
      expect(File.exist?(File.join(tmpdir, 'bootstrapped_settings.json'))).to be(false)
    end

    it 'overwrites existing subsystem files regardless of force flag' do
      transport_path = File.join(tmpdir, 'transport.json')
      File.write(transport_path, JSON.generate({ transport: { host: 'old-host', port: 5672 } }))

      config = { transport: { host: 'new-host' } }
      described_class.write_config(config, force: false)

      result = JSON.parse(File.read(transport_path), symbolize_names: true)
      expect(result).to eq({ transport: { host: 'new-host' } })
    end

    it 'deep merges remainder with existing bootstrapped_settings.json when force is false' do
      bootstrapped_path = File.join(tmpdir, 'bootstrapped_settings.json')
      File.write(bootstrapped_path, JSON.generate({ old_key: 'keep', nested: { a: 1, b: 2 } }))

      config = { nested: { b: 99, c: 3 }, new_key: 'added' }
      described_class.write_config(config, force: false)

      result = JSON.parse(File.read(bootstrapped_path), symbolize_names: true)
      expect(result[:old_key]).to eq('keep')
      expect(result[:nested]).to eq({ a: 1, b: 99, c: 3 })
      expect(result[:new_key]).to eq('added')
    end

    it 'overwrites bootstrapped_settings.json with force: true' do
      bootstrapped_path = File.join(tmpdir, 'bootstrapped_settings.json')
      File.write(bootstrapped_path, JSON.generate({ old_key: 'should_be_gone' }))

      config = { new_key: 'only_this' }
      described_class.write_config(config, force: true)

      result = JSON.parse(File.read(bootstrapped_path), symbolize_names: true)
      expect(result.keys).to eq([:new_key])
    end

    it 'does not mutate the original config hash' do
      config = { transport: { host: 'localhost' }, llm: { enabled: true }, app: 'test' }
      original_keys = config.keys.dup
      described_class.write_config(config)
      expect(config.keys).to eq(original_keys)
    end

    it 'creates the settings directory if it does not exist' do
      nested = File.join(tmpdir, 'nested', 'settings')
      stub_const('Legion::CLI::ConfigImport::SETTINGS_DIR', nested)
      described_class.write_config({ logging: { level: 'info' } })
      expect(Dir.exist?(nested)).to be(true)
    end

    it 'writes all recognized subsystem key types' do
      config = described_class::SUBSYSTEM_KEYS.to_h { |k| [k, { enabled: true }] }
      paths = described_class.write_config(config)

      described_class::SUBSYSTEM_KEYS.each do |key|
        expect(File.exist?(File.join(tmpdir, "#{key}.json"))).to be(true)
      end
      expect(paths.size).to eq(described_class::SUBSYSTEM_KEYS.size)
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
