# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/doctor/result'
require 'legion/cli/doctor/tls_check'

RSpec.describe Legion::CLI::Doctor::TlsCheck do
  subject(:check) { described_class.new }

  describe '#name' do
    it 'returns TLS' do
      expect(check.name).to eq('TLS')
    end
  end

  describe '#run' do
    context 'when Legion::Settings is not defined' do
      before { hide_const('Legion::Settings') }

      it 'returns skip' do
        result = check.run
        expect(result.status).to eq(:skip)
      end
    end

    context 'when all TLS is disabled' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
      end

      it 'returns pass with a note that TLS is not enabled' do
        result = check.run
        expect(result.status).to eq(:pass)
        expect(result.message).to match(/not enabled/i)
      end
    end

    context 'when transport TLS is enabled with verify peer' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { enabled: true, verify: 'peer', ca: nil, cert: nil, key: nil } }
        )
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
      end

      it 'returns pass' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when transport TLS is enabled with verify none' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { enabled: true, verify: 'none' } }
        )
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
      end

      it 'returns warn' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to match(/verify.*none/i)
      end
    end

    context 'when database TLS is enabled but sslmode is require in production' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:data).and_return(
          { tls: { enabled: true, sslmode: 'require' }, adapter: 'postgres' }
        )
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:dig).with(:env).and_return('production')
      end

      it 'returns warn' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to match(/sslmode/i)
      end
    end

    context 'when database TLS is enabled with verify-full' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:data).and_return(
          { tls: { enabled: true, sslmode: 'verify-full' }, adapter: 'postgres' }
        )
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
      end

      it 'returns pass' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when a cert file does not exist' do
      let(:missing_cert) { '/nonexistent/server.crt' }

      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return(
          { tls: { enabled: true, verify: 'peer', cert: missing_cert } }
        )
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return({ tls: { enabled: false } })
      end

      it 'returns warn about the missing cert' do
        result = check.run
        expect(result.status).to eq(:warn)
        expect(result.message).to include(missing_cert)
      end
    end

    context 'when api TLS is enabled with cert and key present' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return(
          { tls: { enabled: true, cert: __FILE__, key: __FILE__ } }
        )
      end

      it 'returns pass' do
        result = check.run
        expect(result.status).to eq(:pass)
      end
    end

    context 'when api TLS is enabled but cert is missing' do
      before do
        allow(Legion::Settings).to receive(:[]).with(:transport).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:data).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:cache).and_return({ tls: { enabled: false } })
        allow(Legion::Settings).to receive(:[]).with(:api).and_return(
          { tls: { enabled: true, cert: nil, key: nil } }
        )
      end

      it 'returns fail' do
        result = check.run
        expect(result.status).to eq(:fail)
        expect(result.message).to match(/api.tls/i)
      end
    end
  end
end
