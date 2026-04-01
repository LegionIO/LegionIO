# frozen_string_literal: true

require 'spec_helper'
require 'legion/trigger/envelope'

RSpec.describe Legion::Trigger::Envelope do
  let(:envelope) do
    described_class.new(
      source: 'github', event_type: 'pull_request', action: 'opened',
      delivery_id: 'abc-123', verified: true, payload: { number: 42 }
    )
  end

  describe '#routing_key' do
    it 'builds from source and event_type' do
      expect(envelope.routing_key).to eq('trigger.github.pull_request')
    end
  end

  describe '#correlation_id' do
    it 'auto-generates when not provided' do
      expect(envelope.correlation_id).to start_with('leg-')
    end

    it 'uses provided value' do
      env = described_class.new(source: 'github', event_type: 'push', payload: {},
                                correlation_id: 'custom-id')
      expect(env.correlation_id).to eq('custom-id')
    end
  end

  describe '#to_h' do
    it 'includes all fields' do
      h = envelope.to_h
      expect(h[:source]).to eq('github')
      expect(h[:event_type]).to eq('pull_request')
      expect(h[:action]).to eq('opened')
      expect(h[:delivery_id]).to eq('abc-123')
      expect(h[:verified]).to be true
      expect(h[:payload]).to eq({ number: 42 })
      expect(h[:received_at]).to be_a(String)
    end
  end
end
