# frozen_string_literal: true

require 'spec_helper'
require 'legion/region'

RSpec.describe Legion::Region do
  before do
    described_class.reset!
    allow(Legion::Settings).to receive(:dig).and_call_original
  end

  after do
    described_class.reset!
  end

  describe '.current' do
    context 'when settings has a current region' do
      it 'returns the region from settings' do
        allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return('us-east-1')
        expect(described_class.current).to eq('us-east-1')
      end
    end

    context 'when settings returns nil' do
      it 'falls back to detect_from_metadata' do
        allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return(nil)
        allow(described_class).to receive(:detect_from_metadata).and_return('us-west-2')
        expect(described_class.current).to eq('us-west-2')
      end

      it 'caches a missing metadata result' do
        allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return(nil)
        allow(described_class).to receive(:detect_from_metadata).and_return(nil)

        2.times { expect(described_class.current).to be_nil }
        expect(described_class).to have_received(:detect_from_metadata).once
      end
    end

    context 'when settings raises an error' do
      it 'returns nil' do
        allow(Legion::Settings).to receive(:dig).with(:region, :current).and_raise(StandardError, 'settings unavailable')
        expect(described_class.current).to be_nil
      end
    end
  end

  describe '.local?' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return('us-east-1')
      allow(described_class).to receive(:detect_from_metadata).and_return(nil)
    end

    it 'returns true when target_region is nil' do
      expect(described_class.local?(nil)).to be true
    end

    it 'returns true when target_region equals current region' do
      expect(described_class.local?('us-east-1')).to be true
    end

    it 'returns false when target_region differs from current region' do
      expect(described_class.local?('eu-west-1')).to be false
    end
  end

  describe '.affinity_for' do
    before do
      allow(Legion::Settings).to receive(:dig).with(:region, :current).and_return('us-east-1')
      allow(described_class).to receive(:detect_from_metadata).and_return(nil)
    end

    it 'returns :local when message is from the same region' do
      expect(described_class.affinity_for('us-east-1', 'require_local')).to eq(:local)
    end

    it 'returns :local when affinity is "any" regardless of region' do
      expect(described_class.affinity_for('eu-west-1', 'any')).to eq(:local)
    end

    it 'returns :local when message_region is nil' do
      expect(described_class.affinity_for(nil, 'require_local')).to eq(:local)
    end

    it 'returns :remote when affinity is "prefer_local" and region differs' do
      expect(described_class.affinity_for('eu-west-1', 'prefer_local')).to eq(:remote)
    end

    it 'returns :reject when affinity is "require_local" and region differs' do
      expect(described_class.affinity_for('eu-west-1', 'require_local')).to eq(:reject)
    end
  end

  describe '.detect_from_metadata' do
    context 'AWS IMDSv2 succeeds' do
      it 'returns the AWS region' do
        token_response = instance_double(Net::HTTPSuccess, body: 'fake-token', is_a?: true)
        region_response = instance_double(Net::HTTPSuccess, body: 'us-east-2', is_a?: true)

        allow(token_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(region_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        call_count = 0
        allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
          call_count += 1
          http = instance_double(Net::HTTP)
          if call_count == 1
            allow(http).to receive(:request).and_return(token_response)
          else
            allow(http).to receive(:request).and_return(region_response)
          end
          block.call(http)
        end

        expect(described_class.send(:detect_from_metadata)).to eq('us-east-2')
      end
    end

    context 'AWS IMDS fails, Azure IMDS succeeds' do
      it 'returns the Azure region' do
        azure_response = instance_double(Net::HTTPSuccess, body: 'eastus', is_a?: true)
        allow(azure_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        call_count = 0
        allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
          call_count += 1
          raise Errno::EHOSTUNREACH, 'no route' if call_count == 1

          http = instance_double(Net::HTTP)
          allow(http).to receive(:request).and_return(azure_response)
          block.call(http)
        end

        expect(described_class.send(:detect_from_metadata)).to eq('eastus')
      end
    end

    context 'both AWS and Azure IMDS fail' do
      it 'returns nil' do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::EHOSTUNREACH, 'no route')
        expect(described_class.send(:detect_from_metadata)).to be_nil
      end
    end

    context 'when Azure metadata times out' do
      it 'suppresses expected timeout logging' do
        allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)
        allow(Legion::Logging).to receive(:debug)

        expect(described_class.send(:detect_from_metadata)).to be_nil
        expect(Legion::Logging).not_to have_received(:debug).with(/detect_azure_region failed/)
      end
    end
  end

  describe '.primary' do
    it 'returns the primary region from settings' do
      allow(Legion::Settings).to receive(:dig).with(:region, :primary).and_return('us-east-1')
      expect(described_class.primary).to eq('us-east-1')
    end

    it 'returns nil when not configured' do
      allow(Legion::Settings).to receive(:dig).with(:region, :primary).and_return(nil)
      expect(described_class.primary).to be_nil
    end
  end

  describe '.failover' do
    it 'returns the failover region from settings' do
      allow(Legion::Settings).to receive(:dig).with(:region, :failover).and_return('us-west-2')
      expect(described_class.failover).to eq('us-west-2')
    end

    it 'returns nil when not configured' do
      allow(Legion::Settings).to receive(:dig).with(:region, :failover).and_return(nil)
      expect(described_class.failover).to be_nil
    end
  end

  describe '.peers' do
    it 'returns the peers array from settings' do
      allow(Legion::Settings).to receive(:dig).with(:region, :peers).and_return(%w[eu-west-1 ap-southeast-1])
      expect(described_class.peers).to eq(%w[eu-west-1 ap-southeast-1])
    end

    it 'returns an empty array when not configured' do
      allow(Legion::Settings).to receive(:dig).with(:region, :peers).and_return(nil)
      expect(described_class.peers).to eq([])
    end
  end
end
