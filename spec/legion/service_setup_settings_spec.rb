# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'

RSpec.describe Legion::Service do
  describe '#setup_settings' do
    let(:service) { described_class.allocate }

    before do
      stub_const('Legion::Settings', Class.new do
        def self.load(**); end
      end)
      stub_const('Legion::Settings::Loader', Class.new do
        def self.default_directories
          ['/home/test/.legionio/settings', '/etc/legionio/settings']
        end
      end)
      stub_const('Legion::Readiness', Class.new do
        def self.mark_ready(*); end
      end)
      allow(Legion::Logging).to receive(:info)
      allow(service.class).to receive(:log_privacy_mode_status)
    end

    it 'loads settings from existing canonical directories' do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:exist?).with('/etc/legionio/settings').and_return(true)

      expect(Legion::Settings).to receive(:load).with(config_dirs: ['/etc/legionio/settings'])
      service.send(:setup_settings)
    end

    it 'filters out non-existent directories' do
      allow(Dir).to receive(:exist?).and_return(false)

      expect(Legion::Settings).to receive(:load).with(config_dirs: [])
      service.send(:setup_settings)
    end

    it 'marks settings as ready' do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Legion::Settings).to receive(:load)

      expect(Legion::Readiness).to receive(:mark_ready).with(:settings)
      service.send(:setup_settings)
    end
  end

  describe 'logging level resolution' do
    let(:service) { described_class.allocate }

    before do
      allow(Legion::Logging).to receive(:setup)
    end

    it 'uses configured logging level when no CLI override is provided' do
      allow(Legion::Settings).to receive(:[]).with(:logging).and_return({ level: 'info' })

      expect(service.send(:bootstrap_log_level, nil)).to eq('info')
    end

    it 'uses CLI log level when one is provided' do
      allow(Legion::Settings).to receive(:[]).with(:logging).and_return({ level: 'info' })

      expect(service.send(:bootstrap_log_level, 'debug')).to eq('debug')
    end

    it 'reconfigures to the settings level when CLI override is nil' do
      allow(Legion::Settings).to receive(:[]).with(:logging).and_return(
        {
          level:       'info',
          format:      'text',
          log_file:    nil,
          log_stdout:  true,
          trace:       true,
          async:       true,
          include_pid: false
        }
      )

      expect(Legion::Logging).to receive(:setup).with(
        level:       'info',
        format:      :text,
        log_file:    nil,
        log_stdout:  true,
        trace:       true,
        async:       true,
        include_pid: false,
        color:       true
      )

      service.send(:reconfigure_logging, nil)
    end
  end
end
