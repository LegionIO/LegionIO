# frozen_string_literal: true

require_relative 'api_spec_helper'

RSpec.describe 'TBI Patterns API' do
  include Rack::Test::Methods

  def app = Legion::API

  before(:all) { ApiSpecSetup.configure_settings }

  describe 'POST /api/tbi/patterns/export' do
    it 'returns 503 when data is not connected' do
      post '/api/tbi/patterns/export',
           Legion::JSON.dump({ pattern_type: 'behavioral', description: 'x', tier: 'tier1', pattern_data: {} }),
           'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/tbi/patterns' do
    it 'returns 503 when data is not connected' do
      get '/api/tbi/patterns'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/tbi/patterns/:id' do
    it 'returns 503 when data is not connected' do
      get '/api/tbi/patterns/1'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'PATCH /api/tbi/patterns/:id/score' do
    it 'returns 503 when data is not connected' do
      patch '/api/tbi/patterns/1/score',
            Legion::JSON.dump({ invocation_count: 10, success_rate: 0.9 }),
            'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(503)
    end
  end

  describe 'GET /api/tbi/patterns/discover' do
    it 'returns 501 not implemented' do
      get '/api/tbi/patterns/discover'
      expect(last_response.status).to eq(501)
      expect(Legion::JSON.load(last_response.body)[:error][:code]).to eq('not_implemented')
    end
  end

  describe 'Routes::TbiPatterns helpers' do
    let(:mod) { Legion::API::Routes::TbiPatterns }

    describe '.serialize_pattern_data' do
      it 'returns a String unchanged' do
        expect(mod.serialize_pattern_data('foo')).to eq('foo')
      end

      it 'JSON-encodes a hash' do
        result = mod.serialize_pattern_data({ a: 1 })
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end

      it 'falls back gracefully when JSON encoding raises' do
        call_count = 0
        allow(Legion::JSON).to receive(:dump) do |arg|
          call_count += 1
          raise StandardError, 'encoding failure' if call_count == 1

          arg.to_s
        end
        result = mod.serialize_pattern_data({ broken: true })
        expect(result).to be_a(String)
      end
    end

    describe '.parse_integer' do
      it 'returns default for nil' do
        expect(mod.parse_integer(nil, 5)).to eq(5)
      end

      it 'returns default for blank string' do
        expect(mod.parse_integer('   ', 5)).to eq(5)
      end

      it 'returns default for non-numeric input' do
        expect(mod.parse_integer('abc', 7)).to eq(7)
      end

      it 'parses a valid integer string' do
        expect(mod.parse_integer('42', 0)).to eq(42)
      end

      it 'parses a numeric value directly' do
        expect(mod.parse_integer(10, 0)).to eq(10)
      end
    end

    describe '.parse_float' do
      it 'returns default for nil' do
        expect(mod.parse_float(nil, 1.0)).to eq(1.0)
      end

      it 'returns default for blank string' do
        expect(mod.parse_float('   ', 1.5)).to eq(1.5)
      end

      it 'returns default for non-numeric input' do
        expect(mod.parse_float('bad', 2.0)).to eq(2.0)
      end

      it 'parses a valid float string' do
        expect(mod.parse_float('0.75', 0.0)).to be_within(0.001).of(0.75)
      end

      it 'parses a numeric value directly' do
        expect(mod.parse_float(0.5, 0.0)).to be_within(0.001).of(0.5)
      end
    end

    describe '.compute_quality' do
      it 'returns a float between 0 and 1' do
        score = mod.compute_quality(invocation_count: 50, success_rate: 0.8, tier: 'tier3')
        expect(score).to be_a(Float)
        expect(score).to be_between(0.0, 1.0)
      end

      it 'produces higher scores for higher invocation counts' do
        low  = mod.compute_quality(invocation_count: 0,   success_rate: 0.5, tier: 'tier1')
        high = mod.compute_quality(invocation_count: 100, success_rate: 0.5, tier: 'tier1')
        expect(high).to be > low
      end
    end

    describe '.anonymize' do
      it 'strips identifying keys' do
        body = { pattern_type: 'x', tier: 'tier1', description: 'y',
                 node_id: 'abc', hostname: 'myhost', ip_address: '10.0.0.1', worker_id: 'w1' }
        result = mod.anonymize(body)
        expect(result.keys).not_to include(:node_id, :hostname, :ip_address, :worker_id)
      end

      it 'includes a 16-char source_hash' do
        body = { pattern_type: 'behavioral', tier: 'tier2', description: 'test' }
        result = mod.anonymize(body)
        expect(result[:source_hash]).to be_a(String)
        expect(result[:source_hash].length).to eq(16)
      end

      it 'produces the same hash for identical inputs' do
        body = { pattern_type: 'x', tier: 'tier1', description: 'y' }
        expect(mod.anonymize(body)[:source_hash]).to eq(mod.anonymize(body)[:source_hash])
      end
    end
  end
end
