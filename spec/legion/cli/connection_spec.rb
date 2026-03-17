# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/error'
require 'legion/cli/connection'

# Pre-load optional gems so their methods exist when mocks are set up.
# Connection's ensure_* methods call `require 'legion/X'` (no-op once loaded)
# followed by methods on the module. If we mock before the methods are defined,
# RSpec cannot intercept them.
begin
  require 'legion/data'
rescue LoadError
  module Legion
    module Data
      module Settings
        def self.default = {}
      end

      def self.setup(**) = nil
      def self.shutdown(**) = nil
    end
  end
  $LOADED_FEATURES << 'legion/data'
end
require 'legion/crypt'
require 'legion/cache'

RSpec.describe Legion::CLI::Connection do
  before do
    %i[@logging_ready @settings_ready @data_ready @transport_ready
       @crypt_ready @cache_ready @llm_ready @config_dir @log_level].each do |ivar|
      described_class.instance_variable_set(ivar, nil)
    end
  end

  def stub_logging_and_settings
    allow(Legion::Logging).to receive(:setup)
    allow(Legion::Settings).to receive(:load)
  end

  # ---------------------------------------------------------------------------
  # ensure_logging
  # ---------------------------------------------------------------------------
  describe '.ensure_logging' do
    before { allow(Legion::Logging).to receive(:setup) }

    it 'calls Legion::Logging.setup with the default error log level' do
      described_class.ensure_logging
      expect(Legion::Logging).to have_received(:setup).with(log_level: 'error', level: 'error', trace: false)
    end

    it 'sets @logging_ready to true' do
      described_class.ensure_logging
      expect(described_class.instance_variable_get(:@logging_ready)).to be(true)
    end

    it 'is idempotent: does not call setup a second time' do
      described_class.ensure_logging
      described_class.ensure_logging
      expect(Legion::Logging).to have_received(:setup).once
    end

    it 'respects a custom log_level' do
      described_class.log_level = 'debug'
      described_class.ensure_logging
      expect(Legion::Logging).to have_received(:setup).with(log_level: 'debug', level: 'debug', trace: false)
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_settings
  # ---------------------------------------------------------------------------
  describe '.ensure_settings' do
    before { stub_logging_and_settings }

    it 'calls ensure_logging first' do
      described_class.ensure_settings
      expect(Legion::Logging).to have_received(:setup)
    end

    it 'calls Legion::Settings.load with a config_dir keyword' do
      described_class.ensure_settings
      expect(Legion::Settings).to have_received(:load).with(config_dir: anything)
    end

    it 'sets @settings_ready to true' do
      described_class.ensure_settings
      expect(described_class.instance_variable_get(:@settings_ready)).to be(true)
    end

    it 'is idempotent: only loads settings once' do
      described_class.ensure_settings
      described_class.ensure_settings
      expect(Legion::Settings).to have_received(:load).once
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_data
  # ---------------------------------------------------------------------------
  describe '.ensure_data' do
    before do
      stub_logging_and_settings
      allow(Legion::Settings).to receive(:merge_settings)
      allow(Legion::Data::Settings).to receive(:default).and_return({})
      allow(Legion::Data).to receive(:setup)
    end

    context 'when legion-data is available and connects successfully' do
      it 'calls Legion::Data.setup' do
        described_class.ensure_data
        expect(Legion::Data).to have_received(:setup)
      end

      it 'sets @data_ready to true' do
        described_class.ensure_data
        expect(described_class.instance_variable_get(:@data_ready)).to be(true)
      end

      it 'is idempotent: does not call setup a second time' do
        described_class.ensure_data
        described_class.ensure_data
        expect(Legion::Data).to have_received(:setup).once
      end
    end

    context 'when the database connection fails with StandardError' do
      before { allow(Legion::Data).to receive(:setup).and_raise(StandardError, 'connection refused') }

      it 'raises CLI::Error with the connection failure message' do
        expect { described_class.ensure_data }.to raise_error(
          Legion::CLI::Error,
          /database connection failed: connection refused/
        )
      end
    end

    context 'when LoadError is raised (gem not available)' do
      before { allow(Legion::Data).to receive(:setup).and_raise(LoadError, 'cannot load') }

      it 'raises CLI::Error with gem install hint' do
        expect { described_class.ensure_data }.to raise_error(
          Legion::CLI::Error,
          /legion-data gem is not installed/
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_transport
  # ---------------------------------------------------------------------------
  describe '.ensure_transport' do
    before do
      stub_logging_and_settings
      allow(Legion::Settings).to receive(:merge_settings)
      allow(Legion::Transport::Settings).to receive(:default).and_return({})
      allow(Legion::Transport::Connection).to receive(:setup)
    end

    context 'when legion-transport is available and connects successfully' do
      it 'calls Legion::Transport::Connection.setup' do
        described_class.ensure_transport
        expect(Legion::Transport::Connection).to have_received(:setup)
      end

      it 'sets @transport_ready to true' do
        described_class.ensure_transport
        expect(described_class.instance_variable_get(:@transport_ready)).to be(true)
      end

      it 'is idempotent: does not call setup a second time' do
        described_class.ensure_transport
        described_class.ensure_transport
        expect(Legion::Transport::Connection).to have_received(:setup).once
      end
    end

    context 'when the transport connection fails with StandardError' do
      before { allow(Legion::Transport::Connection).to receive(:setup).and_raise(StandardError, 'broker unreachable') }

      it 'raises CLI::Error with the connection failure message' do
        expect { described_class.ensure_transport }.to raise_error(
          Legion::CLI::Error,
          /transport connection failed: broker unreachable/
        )
      end
    end

    context 'when LoadError is raised (gem not available)' do
      before { allow(Legion::Transport::Connection).to receive(:setup).and_raise(LoadError, 'cannot load') }

      it 'raises CLI::Error with gem install hint' do
        expect { described_class.ensure_transport }.to raise_error(
          Legion::CLI::Error,
          /legion-transport gem is not installed/
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_crypt
  # ---------------------------------------------------------------------------
  describe '.ensure_crypt' do
    before do
      stub_logging_and_settings
      allow(Legion::Crypt).to receive(:start)
    end

    context 'when legion-crypt is available and starts successfully' do
      it 'calls Legion::Crypt.start' do
        described_class.ensure_crypt
        expect(Legion::Crypt).to have_received(:start)
      end

      it 'sets @crypt_ready to true' do
        described_class.ensure_crypt
        expect(described_class.instance_variable_get(:@crypt_ready)).to be(true)
      end

      it 'is idempotent: does not call start a second time' do
        described_class.ensure_crypt
        described_class.ensure_crypt
        expect(Legion::Crypt).to have_received(:start).once
      end
    end

    context 'when crypt initialization fails with StandardError' do
      before { allow(Legion::Crypt).to receive(:start).and_raise(StandardError, 'vault unavailable') }

      it 'raises CLI::Error with the initialization failure message' do
        expect { described_class.ensure_crypt }.to raise_error(
          Legion::CLI::Error,
          /crypt initialization failed: vault unavailable/
        )
      end
    end

    context 'when LoadError is raised (gem not available)' do
      before { allow(Legion::Crypt).to receive(:start).and_raise(LoadError, 'cannot load') }

      it 'raises CLI::Error with gem install hint' do
        expect { described_class.ensure_crypt }.to raise_error(
          Legion::CLI::Error,
          /legion-crypt gem is not installed/
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_cache
  # ---------------------------------------------------------------------------
  describe '.ensure_cache' do
    before { stub_logging_and_settings }

    context 'when legion-cache is available' do
      it 'sets @cache_ready to true' do
        described_class.ensure_cache
        expect(described_class.instance_variable_get(:@cache_ready)).to be(true)
      end

      it 'is idempotent: does not error on second call' do
        described_class.ensure_cache
        expect { described_class.ensure_cache }.not_to raise_error
        expect(described_class.instance_variable_get(:@cache_ready)).to be(true)
      end
    end

    context 'when LoadError is raised (gem not available)' do
      it 'raises CLI::Error with gem install hint' do
        # Intercept the private `require` method on the module's singleton class.
        # We pass all other require calls through so the ensure chain continues.
        allow(described_class).to receive(:require).and_wrap_original do |orig, *args|
          raise LoadError, "cannot load such file -- #{args.first}" if args.first == 'legion/cache'

          orig.call(*args)
        end
        described_class.instance_variable_set(:@cache_ready, nil)
        expect { described_class.ensure_cache }.to raise_error(
          Legion::CLI::Error,
          /legion-cache gem is not installed/
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Predicate methods
  # ---------------------------------------------------------------------------
  describe '.settings?' do
    it 'returns false when not yet loaded' do
      expect(described_class.settings?).to be(false)
    end

    it 'returns true after ensure_settings succeeds' do
      stub_logging_and_settings
      described_class.ensure_settings
      expect(described_class.settings?).to be(true)
    end
  end

  describe '.data?' do
    it 'returns false when not yet connected' do
      expect(described_class.data?).to be(false)
    end

    it 'returns true after ensure_data succeeds' do
      stub_logging_and_settings
      allow(Legion::Settings).to receive(:merge_settings)
      allow(Legion::Data::Settings).to receive(:default).and_return({})
      allow(Legion::Data).to receive(:setup)
      described_class.ensure_data
      expect(described_class.data?).to be(true)
    end
  end

  describe '.transport?' do
    it 'returns false when not yet connected' do
      expect(described_class.transport?).to be(false)
    end

    it 'returns true after ensure_transport succeeds' do
      stub_logging_and_settings
      allow(Legion::Settings).to receive(:merge_settings)
      allow(Legion::Transport::Settings).to receive(:default).and_return({})
      allow(Legion::Transport::Connection).to receive(:setup)
      described_class.ensure_transport
      expect(described_class.transport?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # shutdown
  # ---------------------------------------------------------------------------
  describe '.shutdown' do
    context 'when no subsystems are ready' do
      it 'does not raise' do
        expect { described_class.shutdown }.not_to raise_error
      end
    end

    context 'when transport is ready' do
      before do
        described_class.instance_variable_set(:@transport_ready, true)
        allow(Legion::Transport::Connection).to receive(:shutdown)
      end

      it 'shuts down transport' do
        described_class.shutdown
        expect(Legion::Transport::Connection).to have_received(:shutdown)
      end
    end

    context 'when data is ready' do
      before do
        described_class.instance_variable_set(:@data_ready, true)
        allow(Legion::Data).to receive(:shutdown)
      end

      it 'shuts down data' do
        described_class.shutdown
        expect(Legion::Data).to have_received(:shutdown)
      end
    end

    context 'when cache is ready' do
      before do
        described_class.instance_variable_set(:@cache_ready, true)
        allow(Legion::Cache).to receive(:shutdown)
      end

      it 'shuts down cache' do
        described_class.shutdown
        expect(Legion::Cache).to have_received(:shutdown)
      end
    end

    context 'when crypt is ready' do
      before do
        described_class.instance_variable_set(:@crypt_ready, true)
        allow(Legion::Crypt).to receive(:shutdown)
      end

      it 'shuts down crypt' do
        described_class.shutdown
        expect(Legion::Crypt).to have_received(:shutdown)
      end
    end

    context 'when a shutdown call raises an error' do
      before do
        described_class.instance_variable_set(:@transport_ready, true)
        allow(Legion::Transport::Connection).to receive(:shutdown).and_raise(StandardError, 'shutdown error')
      end

      it 'swallows the error (best-effort)' do
        expect { described_class.shutdown }.not_to raise_error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_config_dir (exercised through ensure_settings)
  # ---------------------------------------------------------------------------
  describe 'resolve_config_dir' do
    before { stub_logging_and_settings }

    context 'when config_dir is set to an existing directory' do
      it 'uses the custom directory' do
        tmpdir = Dir.mktmpdir('legion-cfg')
        begin
          described_class.config_dir = tmpdir
          described_class.ensure_settings
          expect(Legion::Settings).to have_received(:load).with(config_dir: tmpdir)
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end
    end

    context 'when config_dir is set but does not exist' do
      it 'falls through to fallback paths and still calls Settings.load' do
        described_class.config_dir = '/nonexistent/path/that/does/not/exist'
        described_class.ensure_settings
        expect(Legion::Settings).to have_received(:load).with(config_dir: anything)
      end
    end

    context 'when none of the standard paths exist' do
      before { allow(Dir).to receive(:exist?).and_return(false) }

      it 'falls back to the gem lib directory and calls Settings.load with a string' do
        captured_dir = nil
        allow(Legion::Settings).to receive(:load) { |config_dir:| captured_dir = config_dir }
        described_class.ensure_settings
        expect(captured_dir).to be_a(String)
        expect(captured_dir).not_to be_empty
      end
    end

    context 'when /etc/legionio exists' do
      before do
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with('/etc/legionio').and_return(true)
      end

      it 'uses /etc/legionio' do
        described_class.ensure_settings
        expect(Legion::Settings).to have_received(:load).with(config_dir: '/etc/legionio')
      end
    end

    context 'when ~/legionio exists but /etc/legionio does not' do
      let(:home_dir) { File.join(Dir.home, 'legionio') }
      let(:settings_dir) { File.join(Dir.home, '.legionio', 'settings') }

      before do
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with('/etc/legionio').and_return(false)
        allow(Dir).to receive(:exist?).with(settings_dir).and_return(false)
        allow(Dir).to receive(:exist?).with(home_dir).and_return(true)
      end

      it 'uses the home directory path' do
        described_class.ensure_settings
        expect(Legion::Settings).to have_received(:load).with(config_dir: home_dir)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # log_level default and writer
  # ---------------------------------------------------------------------------
  describe '.log_level' do
    it 'defaults to "error"' do
      expect(described_class.log_level).to eq('error')
    end

    it 'returns the assigned value after assignment' do
      described_class.log_level = 'warn'
      expect(described_class.log_level).to eq('warn')
    end
  end
end
