# frozen_string_literal: true

require 'spec_helper'
require 'legion/webhooks'

RSpec.describe Legion::Webhooks do
  let(:connection) { instance_double('Sequel::Database') }
  let(:webhooks_dataset) { instance_double('Sequel::Dataset') }
  let(:active_webhooks_dataset) { instance_double('Sequel::Dataset') }
  let(:deliveries_dataset) { instance_double('Sequel::Dataset') }
  let(:dead_letters_dataset) { instance_double('Sequel::Dataset') }
  let(:delete_dataset) { instance_double('Sequel::Dataset') }

  before do
    described_class.send(:invalidate_dispatch_cache!)

    stub_const('Legion::Data', Module.new do
      class << self
        attr_accessor :connection
      end
    end)
    Legion::Data.connection = connection

    allow(connection).to receive(:[]).with(:webhooks).and_return(webhooks_dataset)
    allow(connection).to receive(:[]).with(:webhook_deliveries).and_return(deliveries_dataset)
    allow(connection).to receive(:[]).with(:webhook_dead_letters).and_return(dead_letters_dataset)

    allow(deliveries_dataset).to receive(:insert)
    allow(dead_letters_dataset).to receive(:insert)
    allow(webhooks_dataset).to receive(:where).with(status: 'active').and_return(active_webhooks_dataset)
    allow(active_webhooks_dataset).to receive(:all).and_return([])
  end

  after do
    described_class.send(:invalidate_dispatch_cache!)
  end

  describe '.compute_signature' do
    it 'returns HMAC-SHA256 hex digest' do
      sig = described_class.compute_signature('secret', '{"event":"test"}')
      expect(sig).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'is deterministic' do
      s1 = described_class.compute_signature('key', 'body')
      s2 = described_class.compute_signature('key', 'body')
      expect(s1).to eq(s2)
    end
  end

  describe '.register' do
    it 'invalidates the dispatch cache after insert' do
      allow(webhooks_dataset).to receive(:insert).and_return(42)
      described_class.instance_variable_set(:@active_webhooks_cache, [:cached])
      described_class.instance_variable_set(:@pattern_cache, { stale: true })

      result = described_class.register(url: 'https://example.com/hook', secret: 'abc', event_types: ['test.*'])

      expect(result).to eq({ registered: true, id: 42 })
      expect(described_class.instance_variable_get(:@active_webhooks_cache)).to be_nil
      expect(described_class.instance_variable_get(:@pattern_cache)).to eq({})
    end
  end

  describe '.unregister' do
    it 'invalidates the dispatch cache after delete' do
      allow(webhooks_dataset).to receive(:where).with(id: 7).and_return(delete_dataset)
      allow(delete_dataset).to receive(:delete)
      described_class.instance_variable_set(:@active_webhooks_cache, [:cached])
      described_class.instance_variable_set(:@pattern_cache, { stale: true })

      result = described_class.unregister(id: 7)

      expect(result).to eq({ unregistered: true })
      expect(described_class.instance_variable_get(:@active_webhooks_cache)).to be_nil
      expect(described_class.instance_variable_get(:@pattern_cache)).to eq({})
    end
  end

  describe '.dispatch' do
    let(:webhook) do
      {
        id:          1,
        url:         'https://example.com/hook',
        secret:      'abc',
        event_types: '["alert.*"]',
        max_retries: 0,
        updated_at:  Time.utc(2026, 4, 2, 19, 0, 0)
      }
    end

    before do
      allow(active_webhooks_dataset).to receive(:all).and_return([webhook])
      allow(described_class).to receive(:perform_delivery_request).and_return(instance_double('Net::HTTPResponse', code: '200'))
    end

    it 'returns nil when data unavailable' do
      Legion::Data.connection = nil
      expect(described_class.dispatch('test.event', {})).to be_nil
    end

    it 'caches the active webhook rows and parsed event patterns between dispatches' do
      allow(Legion::JSON).to receive(:load).and_call_original

      2.times { described_class.dispatch('alert.triggered', foo: 'bar') }

      expect(active_webhooks_dataset).to have_received(:all).once
      expect(Legion::JSON).to have_received(:load).with('["alert.*"]').once
      expect(deliveries_dataset).to have_received(:insert).twice
    end

    it 'ignores events that do not match the configured patterns' do
      described_class.dispatch('audit.created', foo: 'bar')

      expect(described_class).not_to have_received(:perform_delivery_request)
      expect(deliveries_dataset).not_to have_received(:insert)
    end
  end

  describe '.deliver' do
    let(:webhook) do
      {
        id:          9,
        url:         'https://example.com/hook',
        secret:      'abc',
        event_types: '["test.event"]',
        max_retries: max_retries,
        updated_at:  Time.utc(2026, 4, 2, 19, 0, 0)
      }
    end
    let(:max_retries) { 2 }

    it 'retries non-success HTTP responses up to the configured retry limit' do
      responses = [
        instance_double('Net::HTTPResponse', code: '500'),
        instance_double('Net::HTTPResponse', code: '502'),
        instance_double('Net::HTTPResponse', code: '200')
      ]
      allow(described_class).to receive(:perform_delivery_request).and_return(*responses)

      result = described_class.deliver(webhook, 'test.event', { payload: true })

      expect(result).to eq({ delivered: true, status: 200 })
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: 500, success: false, attempt: 1, error: 'http_status=500')
      ).once
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: 502, success: false, attempt: 2, error: 'http_status=502')
      ).once
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: 200, success: true, attempt: 3, error: nil)
      ).once
      expect(dead_letters_dataset).not_to have_received(:insert)
    end

    it 'dead letters after the configured retry limit is exhausted on exceptions' do
      allow(described_class).to receive(:perform_delivery_request).and_raise(StandardError, 'boom')
      limited_webhook = webhook.merge(max_retries: 1)

      result = described_class.deliver(limited_webhook, 'test.event', { payload: true })

      expect(result).to include(delivered: false, dead_lettered: true, error: 'boom')
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: nil, success: false, attempt: 1, error: 'boom')
      ).once
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: nil, success: false, attempt: 2, error: 'boom')
      ).once
      expect(dead_letters_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', attempts: 2, last_error: 'boom')
      ).once
    end

    it 'does not retry when max_retries is zero' do
      allow(described_class).to receive(:perform_delivery_request).and_return(instance_double('Net::HTTPResponse', code: '503'))
      no_retry_webhook = webhook.merge(max_retries: 0)

      result = described_class.deliver(no_retry_webhook, 'test.event', { payload: true })

      expect(result).to include(delivered: false, dead_lettered: true, status: 503)
      expect(deliveries_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', response_status: 503, success: false, attempt: 1, error: 'http_status=503')
      ).once
      expect(dead_letters_dataset).to have_received(:insert).with(
        hash_including(webhook_id: 9, event_name: 'test.event', attempts: 1, last_error: 'http_status=503')
      ).once
    end
  end
end
