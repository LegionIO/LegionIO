# frozen_string_literal: true

require 'spec_helper'
require 'legion/trigger'

RSpec.describe Legion::Trigger::Sources::Github do
  let(:adapter) { described_class.new }

  describe '#normalize' do
    it 'extracts github-specific fields' do
      headers = {
        'HTTP_X_GITHUB_EVENT'    => 'pull_request',
        'HTTP_X_GITHUB_DELIVERY' => 'delivery-uuid'
      }
      body = { 'action' => 'opened', 'number' => 42 }

      result = adapter.normalize(headers: headers, body: body)
      expect(result[:source]).to eq('github')
      expect(result[:event_type]).to eq('pull_request')
      expect(result[:action]).to eq('opened')
      expect(result[:delivery_id]).to eq('delivery-uuid')
    end
  end

  describe '#verify_signature' do
    let(:secret) { 'test-secret' }
    let(:body_raw) { '{"action":"opened"}' }

    it 'returns true for valid HMAC' do
      digest = OpenSSL::HMAC.hexdigest('SHA256', secret, body_raw)
      headers = { 'HTTP_X_HUB_SIGNATURE_256' => "sha256=#{digest}" }
      expect(adapter.verify_signature(headers: headers, body_raw: body_raw, secret: secret)).to be true
    end

    it 'returns false for invalid HMAC' do
      headers = { 'HTTP_X_HUB_SIGNATURE_256' => 'sha256=bad' }
      expect(adapter.verify_signature(headers: headers, body_raw: body_raw, secret: secret)).to be false
    end

    it 'returns false when header is missing' do
      expect(adapter.verify_signature(headers: {}, body_raw: body_raw, secret: secret)).to be false
    end
  end
end

RSpec.describe Legion::Trigger::Sources::Slack do
  let(:adapter) { described_class.new }

  describe '#normalize' do
    it 'extracts slack-specific fields' do
      body = { 'type' => 'event_callback', 'event_id' => 'ev123', 'event' => { 'type' => 'message' } }
      result = adapter.normalize(headers: {}, body: body)
      expect(result[:source]).to eq('slack')
      expect(result[:event_type]).to eq('event_callback')
      expect(result[:action]).to eq('message')
    end
  end
end

RSpec.describe Legion::Trigger::Sources::Linear do
  let(:adapter) { described_class.new }

  describe '#normalize' do
    it 'extracts linear-specific fields' do
      headers = { 'HTTP_LINEAR_EVENT' => 'Issue', 'HTTP_LINEAR_DELIVERY' => 'del-456' }
      body = { 'action' => 'create', 'type' => 'Issue' }
      result = adapter.normalize(headers: headers, body: body)
      expect(result[:source]).to eq('linear')
      expect(result[:event_type]).to eq('Issue')
      expect(result[:action]).to eq('create')
    end
  end
end
