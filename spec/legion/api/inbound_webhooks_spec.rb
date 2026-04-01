# frozen_string_literal: true

require 'spec_helper'
require 'legion/trigger'

RSpec.describe 'Inbound Webhooks' do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
    allow(Legion::Logging).to receive(:error)
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    hide_const('Legion::Cache') if defined?(Legion::Cache)
  end

  describe 'Legion::Trigger.process via github' do
    let(:headers) do
      { 'HTTP_X_GITHUB_EVENT' => 'pull_request', 'HTTP_X_GITHUB_DELIVERY' => 'del-pr-1' }
    end
    let(:body) { { 'action' => 'opened', 'number' => 1 } }
    let(:body_raw) { '{"action":"opened","number":1}' }

    it 'returns 202-equivalent success with routing key' do
      result = Legion::Trigger.process(
        source_name: 'github', headers: headers, body_raw: body_raw, body: body
      )
      expect(result[:success]).to be true
      expect(result[:routing_key]).to eq('trigger.github.pull_request')
      expect(result[:correlation_id]).to start_with('leg-')
    end
  end

  describe 'Legion::Trigger.process via slack' do
    let(:body) { { 'type' => 'event_callback', 'event_id' => 'ev1', 'event' => { 'type' => 'message' } } }
    let(:body_raw) { '{"type":"event_callback","event_id":"ev1","event":{"type":"message"}}' }

    it 'returns success with slack routing key' do
      result = Legion::Trigger.process(
        source_name: 'slack', headers: {}, body_raw: body_raw, body: body
      )
      expect(result[:success]).to be true
      expect(result[:routing_key]).to eq('trigger.slack.event_callback')
    end
  end

  describe 'Legion::Trigger.registered_sources' do
    it 'includes github, slack, linear' do
      expect(Legion::Trigger.registered_sources).to contain_exactly('github', 'slack', 'linear')
    end
  end

  describe 'unknown source' do
    it 'returns error' do
      result = Legion::Trigger.process(
        source_name: 'unknown', headers: {}, body_raw: '', body: {}
      )
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:unknown_source)
    end
  end
end
