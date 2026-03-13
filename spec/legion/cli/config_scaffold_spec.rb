# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/config_scaffold'
require 'legion/cli/output'
require 'json'
require 'tmpdir'

RSpec.describe Legion::CLI::ConfigScaffold do
  let(:tmpdir) { Dir.mktmpdir('legion-scaffold') }
  let(:formatter) { Legion::CLI::Output::Formatter.new(json: false, color: false) }
  let(:json_formatter) { Legion::CLI::Output::Formatter.new(json: true, color: false) }

  after { FileUtils.rm_rf(tmpdir) }

  def run_scaffold(overrides = {})
    opts = { dir: tmpdir, json: false, full: false, force: false, only: nil }.merge(overrides)
    output = StringIO.new
    exit_code = nil
    begin
      $stdout = output
      exit_code = described_class.run(overrides[:json] ? json_formatter : formatter, opts)
    ensure
      $stdout = STDOUT
    end
    [exit_code, output.string]
  end

  def read_generated(name)
    JSON.parse(File.read(File.join(tmpdir, "#{name}.json")))
  end

  describe '.run' do
    it 'creates all 6 subsystem files' do
      exit_code, = run_scaffold
      expect(exit_code).to eq(0)
      %w[transport data cache crypt logging llm].each do |name|
        expect(File.exist?(File.join(tmpdir, "#{name}.json"))).to be(true)
      end
    end

    it 'creates the output directory if it does not exist' do
      new_dir = File.join(tmpdir, 'nested', 'settings')
      run_scaffold(dir: new_dir)
      expect(Dir.exist?(new_dir)).to be(true)
    end

    context 'minimal mode' do
      before { run_scaffold }

      it 'transport.json has connection host/port/user/password/vhost' do
        config = read_generated('transport')
        conn = config['transport']['connection']
        expect(conn).to include('host' => '127.0.0.1', 'port' => 5672, 'user' => 'guest', 'vhost' => '/')
      end

      it 'data.json has adapter and creds' do
        config = read_generated('data')
        expect(config['data']['adapter']).to eq('sqlite')
        expect(config['data']['creds']['database']).to eq('legionio.db')
      end

      it 'cache.json has driver and servers' do
        config = read_generated('cache')
        expect(config['cache']['driver']).to eq('dalli')
        expect(config['cache']['servers']).to eq(['127.0.0.1:11211'])
      end

      it 'crypt.json has vault and jwt sections' do
        config = read_generated('crypt')
        expect(config['crypt']['vault']['enabled']).to be(false)
        expect(config['crypt']['jwt']['default_algorithm']).to eq('HS256')
      end

      it 'logging.json has level and location' do
        config = read_generated('logging')
        expect(config['logging']['level']).to eq('info')
        expect(config['logging']['location']).to eq('stdout')
      end

      it 'llm.json has providers' do
        config = read_generated('llm')
        expect(config['llm']['enabled']).to be(false)
        expect(config['llm']['providers']).to have_key('anthropic')
        expect(config['llm']['providers']).to have_key('ollama')
      end
    end

    context '--full mode' do
      before { run_scaffold(full: true) }

      it 'transport.json includes channel and queue settings' do
        config = read_generated('transport')
        expect(config['transport']).to have_key('channel')
        expect(config['transport']).to have_key('queues')
        expect(config['transport']).to have_key('exchanges')
        expect(config['transport']).to have_key('messages')
      end

      it 'data.json includes connection and migration settings' do
        config = read_generated('data')
        expect(config['data']).to have_key('connection')
        expect(config['data']).to have_key('migrations')
        expect(config['data']).to have_key('models')
      end

      it 'cache.json includes pool_size and namespace' do
        config = read_generated('cache')
        expect(config['cache']).to have_key('pool_size')
        expect(config['cache']).to have_key('namespace')
        expect(config['cache']).to have_key('failover')
      end

      it 'crypt.json includes cluster_secret and vault kv_path' do
        config = read_generated('crypt')
        expect(config['crypt']).to have_key('cluster_secret')
        expect(config['crypt']['vault']).to have_key('kv_path')
        expect(config['crypt']['jwt']).to have_key('verify_expiration')
      end

      it 'llm.json includes vault_path for providers' do
        config = read_generated('llm')
        expect(config['llm']['providers']['anthropic']).to have_key('vault_path')
        expect(config['llm']['providers']['bedrock']).to have_key('secret_key')
      end
    end

    context '--only flag' do
      it 'creates only specified subsystems' do
        run_scaffold(only: 'transport,data')
        expect(File.exist?(File.join(tmpdir, 'transport.json'))).to be(true)
        expect(File.exist?(File.join(tmpdir, 'data.json'))).to be(true)
        expect(File.exist?(File.join(tmpdir, 'cache.json'))).to be(false)
        expect(File.exist?(File.join(tmpdir, 'llm.json'))).to be(false)
      end

      it 'returns error for unknown subsystems' do
        exit_code, = run_scaffold(only: 'transport,bogus')
        expect(exit_code).to eq(1)
      end
    end

    context 'existing files' do
      before do
        FileUtils.mkdir_p(tmpdir)
        File.write(File.join(tmpdir, 'transport.json'), '{"custom": true}')
      end

      it 'skips existing files by default' do
        run_scaffold
        config = JSON.parse(File.read(File.join(tmpdir, 'transport.json')))
        expect(config).to eq({ 'custom' => true })
      end

      it 'overwrites existing files with --force' do
        run_scaffold(force: true)
        config = read_generated('transport')
        expect(config).to have_key('transport')
      end
    end

    context '--json output' do
      it 'returns created and skipped arrays' do
        output = StringIO.new
        $stdout = output
        described_class.run(json_formatter, { dir: tmpdir, json: true, full: false, force: false, only: nil })
        $stdout = STDOUT
        parsed = JSON.parse(output.string)
        expect(parsed['created'].size).to eq(6)
        expect(parsed['skipped']).to be_empty
      end
    end

    it 'generates valid JSON in all files' do
      run_scaffold(full: true)
      %w[transport data cache crypt logging llm].each do |name|
        path = File.join(tmpdir, "#{name}.json")
        expect { JSON.parse(File.read(path)) }.not_to raise_error
      end
    end
  end
end
