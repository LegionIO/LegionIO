# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'

RSpec.describe Legion::Service do
  describe '#setup_mtls_rotation' do
    let(:service) { described_class.allocate }

    context 'when security.mtls.enabled is false' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:security).and_return(
          { mtls: { enabled: false } }
        )
      end

      it 'does not start CertRotation' do
        cert_rotation_class = double('CertRotationClass')
        stub_const('Legion::Crypt::CertRotation', cert_rotation_class)
        expect(cert_rotation_class).not_to receive(:new)
        service.send(:setup_mtls_rotation)
      end
    end

    context 'when security.mtls.enabled is true' do
      let(:rotation_instance) { double('CertRotation', start: nil, stop: nil) }
      let(:cert_rotation_class) { double('CertRotationClass') }

      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:security).and_return(
          { mtls: { enabled: true } }
        )
        stub_const('Legion::Crypt::CertRotation', cert_rotation_class)
        stub_const('Legion::Crypt::Mtls', Module.new)
        allow(Legion::Crypt::Mtls).to receive(:enabled?).and_return(true)
        allow(cert_rotation_class).to receive(:new).and_return(rotation_instance)
      end

      it 'creates and starts CertRotation' do
        expect(cert_rotation_class).to receive(:new).and_return(rotation_instance)
        expect(rotation_instance).to receive(:start)
        service.send(:setup_mtls_rotation)
      end

      it 'stores the rotation instance' do
        service.send(:setup_mtls_rotation)
        expect(service.instance_variable_get(:@cert_rotation)).to eq rotation_instance
      end
    end

    context 'when security settings are missing entirely' do
      before do
        allow(Legion::Settings).to receive(:[]).and_call_original
        allow(Legion::Settings).to receive(:[]).with(:security).and_return(nil)
      end

      it 'does not raise' do
        expect { service.send(:setup_mtls_rotation) }.not_to raise_error
      end

      it 'does not start CertRotation' do
        cert_rotation_class = double('CertRotationClass')
        stub_const('Legion::Crypt::CertRotation', cert_rotation_class)
        expect(cert_rotation_class).not_to receive(:new)
        service.send(:setup_mtls_rotation)
      end
    end
  end

  describe '#shutdown_mtls_rotation' do
    let(:service) { described_class.allocate }

    context 'when @cert_rotation is set' do
      let(:rotation_instance) { double('CertRotation', stop: nil) }

      before do
        service.instance_variable_set(:@cert_rotation, rotation_instance)
      end

      it 'calls stop on the rotation instance' do
        expect(rotation_instance).to receive(:stop)
        service.send(:shutdown_mtls_rotation)
      end

      it 'nils out @cert_rotation' do
        service.send(:shutdown_mtls_rotation)
        expect(service.instance_variable_get(:@cert_rotation)).to be_nil
      end
    end

    context 'when @cert_rotation is nil' do
      it 'does not raise' do
        expect { service.send(:shutdown_mtls_rotation) }.not_to raise_error
      end
    end
  end
end
