# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Service do
  describe '#setup_api' do
    let(:service) { described_class.allocate }

    before do
      stub_const('Legion::API', Class.new do
        def self.set(*); end

        def self.run!(**); end

        def self.running? = false
      end)
      allow(service).to receive(:require).and_return(true)
    end

    context 'when api.tls.enabled is false (default)' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:api).and_return(
          { port: 4567, bind: '0.0.0.0', tls: { enabled: false } }
        )
      end

      it 'does not configure ssl_bind on puma' do
        expect(Legion::API).not_to receive(:set).with(:ssl_bind_options, anything)
        allow(Legion::API).to receive(:set)
        allow(Thread).to receive(:new).and_return(double(join: nil))
        service.send(:setup_api)
      end
    end

    context 'when api.tls.enabled is true with cert and key' do
      let(:cert_path) { '/etc/ssl/server.crt' }
      let(:key_path)  { '/etc/ssl/server.key' }

      before do
        allow(Legion::Settings).to receive(:[]).with(:api).and_return(
          {
            port: 4567,
            bind: '0.0.0.0',
            tls:  {
              enabled: true,
              cert:    cert_path,
              key:     key_path,
              ca:      nil,
              verify:  'peer'
            }
          }
        )
      end

      it 'sets ssl_bind_options on the Legion::API Sinatra app' do
        ssl_opts = nil
        allow(Legion::API).to receive(:set) do |key, val|
          ssl_opts = val if key == :ssl_bind_options
        end
        allow(Thread).to receive(:new).and_return(double(join: nil))
        service.send(:setup_api)
        expect(ssl_opts).to include(cert: cert_path, key: key_path)
      end

      it 'sets server_settings to include ssl configuration' do
        server_settings = nil
        allow(Legion::API).to receive(:set) do |key, val|
          server_settings = val if key == :server_settings
        end
        allow(Thread).to receive(:new).and_return(double(join: nil))
        service.send(:setup_api)
        expect(server_settings).to be_a(Hash)
      end
    end

    context 'when api.tls.enabled is true but cert is missing' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:api).and_return(
          { port: 4567, bind: '0.0.0.0', tls: { enabled: true, cert: nil, key: nil } }
        )
        allow(Legion::Logging).to receive(:warn)
        allow(Legion::Logging).to receive(:error)
      end

      it 'logs a warning and falls back to plain HTTP' do
        expect(Legion::Logging).to receive(:warn).with(match(/api.tls/i))
        allow(Thread).to receive(:new).and_return(double(join: nil))
        allow(Legion::API).to receive(:set)
        service.send(:setup_api)
      end
    end
  end
end
