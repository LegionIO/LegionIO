# frozen_string_literal: true

require 'spec_helper'
require 'sinatra/base'
require 'legion/api/default_settings'

RSpec.describe Legion::API::Settings do
  describe '.default' do
    subject(:defaults) { described_class.default }

    it 'returns a hash' do
      expect(defaults).to be_a(Hash)
    end

    it 'includes port' do
      expect(defaults[:port]).to eq(4567)
    end

    it 'includes bind' do
      expect(defaults[:bind]).to eq('0.0.0.0')
    end

    it 'includes enabled' do
      expect(defaults[:enabled]).to be(true)
    end

    it 'includes puma thread settings' do
      expect(defaults[:puma][:min_threads]).to eq(10)
      expect(defaults[:puma][:max_threads]).to eq(16)
    end

    it 'includes puma timeout settings' do
      expect(defaults[:puma][:persistent_timeout]).to eq(20)
      expect(defaults[:puma][:first_data_timeout]).to eq(30)
    end

    it 'includes bind_retries' do
      expect(defaults[:bind_retries]).to eq(3)
    end

    it 'includes bind_retry_wait' do
      expect(defaults[:bind_retry_wait]).to eq(2)
    end

    it 'includes tls defaults' do
      expect(defaults[:tls]).to eq({ enabled: false })
    end
  end
end
