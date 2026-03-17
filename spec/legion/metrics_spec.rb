# frozen_string_literal: true

require 'spec_helper'
require 'legion/metrics'

RSpec.describe Legion::Metrics do
  before(:each) { described_class.reset! }
  after(:each) { described_class.reset! }

  describe '.available?' do
    it 'returns false when prometheus-client is absent' do
      hide_const('Prometheus::Client') if defined?(Prometheus::Client)
      expect(described_class.available?).to be false
    end

    it 'returns true when prometheus-client is loaded' do
      stub_const('Prometheus::Client', Module.new)
      expect(described_class.available?).to be true
    end
  end

  describe '.setup' do
    it 'is a no-op when prometheus-client is absent' do
      hide_const('Prometheus::Client') if defined?(Prometheus::Client)
      expect { described_class.setup }.not_to raise_error
    end
  end

  context 'with prometheus-client stubbed' do
    let(:fake_counter) { instance_double('Counter', increment: nil) }
    let(:fake_gauge) { instance_double('Gauge', set: nil) }
    let(:fake_registry) do
      reg = instance_double('Registry')
      allow(reg).to receive(:counter).and_return(fake_counter)
      allow(reg).to receive(:gauge).and_return(fake_gauge)
      reg
    end

    before do
      stub_const('Prometheus::Client', Module.new)
      stub_const('Prometheus::Client::Registry', Class.new)
      allow(Prometheus::Client::Registry).to receive(:new).and_return(fake_registry)
      described_class.setup
    end

    it 'creates a registry' do
      expect(described_class.registry).to eq(fake_registry)
    end

    it 'increments tasks_total on ingress.received' do
      expect(fake_counter).to receive(:increment).with(labels: { status: 'queued' })
      Legion::Events.emit('ingress.received')
    end

    it 'increments tasks_total on runner.success' do
      expect(fake_counter).to receive(:increment).with(labels: { status: 'success' })
      Legion::Events.emit('runner.success')
    end

    it 'increments consent_violations on governance event' do
      expect(fake_counter).to receive(:increment).with(no_args)
      Legion::Events.emit('governance.consent_violation')
    end
  end
end
