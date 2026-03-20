# frozen_string_literal: true

require 'spec_helper'
require 'digest'

unless defined?(Legion::Logging)
  module Legion
    module Logging
      def self.debug(_msg); end
      def self.info(_msg); end
      def self.warn(_msg); end
      def self.error(_msg); end
    end
  end
end

require 'legion/extensions/actors/fingerprint'

RSpec.describe Legion::Extensions::Actors::Fingerprint do
  let(:host) do
    obj = Object.new
    obj.extend(described_class)
    obj
  end

  describe '#skip_if_unchanged?' do
    it 'returns false by default' do
      expect(host.skip_if_unchanged?).to be false
    end
  end

  describe '#fingerprint_source' do
    it 'returns a non-nil string by default' do
      expect(host.fingerprint_source).to be_a(String)
      expect(host.fingerprint_source).not_to be_empty
    end
  end

  describe '#compute_fingerprint' do
    it 'returns a 64-char hex string' do
      fp = host.compute_fingerprint
      expect(fp).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'produces the same value for the same source within the same interval bucket' do
      source = 'stable-content'
      allow(host).to receive(:fingerprint_source).and_return(source)
      expect(host.compute_fingerprint).to eq(host.compute_fingerprint)
    end
  end

  describe '#unchanged?' do
    it 'returns false when @last_fingerprint is nil (first run)' do
      expect(host.unchanged?).to be false
    end

    it 'returns true after the fingerprint is stored and source is stable' do
      allow(host).to receive(:fingerprint_source).and_return('fixed-content')
      host.store_fingerprint!
      expect(host.unchanged?).to be true
    end

    it 'returns false when the fingerprint changes' do
      call_count = 0
      allow(host).to receive(:fingerprint_source) do
        call_count += 1
        call_count == 1 ? 'content-a' : 'content-b'
      end
      host.store_fingerprint!
      expect(host.unchanged?).to be false
    end
  end

  describe '#store_fingerprint!' do
    it 'sets @last_fingerprint to current fingerprint' do
      allow(host).to receive(:fingerprint_source).and_return('my-content')
      host.store_fingerprint!
      expect(host.instance_variable_get(:@last_fingerprint)).to eq(Digest::SHA256.hexdigest('my-content'))
    end
  end

  describe '#skip_or_run' do
    context 'when skip_if_unchanged? is false' do
      it 'always yields' do
        allow(host).to receive(:skip_if_unchanged?).and_return(false)
        allow(host).to receive(:fingerprint_source).and_return('content')
        called = false
        host.skip_or_run { called = true }
        expect(called).to be true
      end
    end

    context 'when skip_if_unchanged? is true and content is unchanged' do
      it 'does not yield after first run' do
        allow(host).to receive(:skip_if_unchanged?).and_return(true)
        allow(host).to receive(:fingerprint_source).and_return('stable')
        call_count = 0
        host.skip_or_run { call_count += 1 }
        host.skip_or_run { call_count += 1 }
        expect(call_count).to eq(1)
      end
    end

    context 'when skip_if_unchanged? is true and content changes' do
      it 'yields on each change' do
        allow(host).to receive(:skip_if_unchanged?).and_return(true)
        sources = %w[content-a content-b content-b content-c]
        call_index = 0
        allow(host).to receive(:fingerprint_source) do
          sources[call_index]
        end
        results = []
        4.times do
          host.skip_or_run { results << sources[call_index] }
          call_index += 1
        end
        expect(results.size).to eq(3)
      end
    end
  end
end
