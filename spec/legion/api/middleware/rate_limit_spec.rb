# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legion/api/middleware/rate_limit'

RSpec.describe Legion::API::Middleware::RateLimit do
  describe Legion::API::Middleware::RateLimit::MemoryStore do
    let(:store) { described_class.new }

    it 'increments and returns count' do
      expect(store.increment('ip:127.0.0.1', 1000)).to eq(1)
      expect(store.increment('ip:127.0.0.1', 1000)).to eq(2)
    end

    it 'returns count for a key' do
      store.increment('ip:127.0.0.1', 1000)
      expect(store.count('ip:127.0.0.1', 1000)).to eq(1)
    end

    it 'returns 0 for unknown key' do
      expect(store.count('ip:unknown', 1000)).to eq(0)
    end

    it 'isolates different windows' do
      store.increment('ip:127.0.0.1', 1000)
      store.increment('ip:127.0.0.1', 1060)
      expect(store.count('ip:127.0.0.1', 1000)).to eq(1)
      expect(store.count('ip:127.0.0.1', 1060)).to eq(1)
    end

    it 'reaps old windows' do
      old_window = (Time.now.to_i / 60 * 60) - 180
      store.increment('ip:old', old_window)
      store.reap!
      expect(store.count('ip:old', old_window)).to eq(0)
    end
  end

  describe 'middleware integration' do
    include Rack::Test::Methods

    let(:inner_app) do
      lambda do |_env|
        [200, { 'content-type' => 'text/plain' }, ['ok']]
      end
    end

    let(:rate_limit_opts) { { enabled: true, per_ip: 3, per_agent: 10, per_tenant: 20 } }

    let(:app) do
      opts = rate_limit_opts
      ia = inner_app
      Rack::Builder.new do
        use Legion::API::Middleware::RateLimit, **opts
        run ia
      end.to_app
    end

    it 'skips health endpoint' do
      10.times { get '/api/health' }
      expect(last_response.status).to eq(200)
      expect(last_response.headers).not_to have_key('X-RateLimit-Limit')
    end

    it 'adds rate limit headers to normal responses' do
      get '/api/test'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['X-RateLimit-Limit']).not_to be_nil
      expect(last_response.headers['X-RateLimit-Remaining']).not_to be_nil
      expect(last_response.headers['X-RateLimit-Reset']).not_to be_nil
    end

    it 'returns 429 when per_ip limit exceeded' do
      3.times do
        get '/api/test'
        expect(last_response.status).to eq(200)
      end
      get '/api/test'
      expect(last_response.status).to eq(429)
      body = Legion::JSON.load(last_response.body)
      expect(body[:error][:code]).to eq('rate_limit_exceeded')
      expect(last_response.headers['Retry-After']).not_to be_nil
    end

    it 'does not include Retry-After on non-429 responses' do
      get '/api/test'
      expect(last_response.status).to eq(200)
      expect(last_response.headers).not_to have_key('Retry-After')
    end

    context 'when disabled' do
      let(:rate_limit_opts) { { enabled: false } }

      it 'passes through without rate limiting' do
        10.times { get '/api/test' }
        expect(last_response.status).to eq(200)
        expect(last_response.headers).not_to have_key('X-RateLimit-Limit')
      end
    end
  end
end
