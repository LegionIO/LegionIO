# frozen_string_literal: true

require 'spec_helper'
require 'legion/telemetry'

RSpec.describe Legion::Telemetry do
  describe '.configure_exporter' do
    before do
      allow(Legion::Settings).to receive(:[]).and_call_original
    end

    it 'returns nil for :none backend' do
      allow(Legion::Settings).to receive(:[]).with(:telemetry).and_return({ tracing: { exporter: :none } })
      expect(described_class.configure_exporter).to be_nil
    end

    it 'returns nil when telemetry settings are empty' do
      allow(Legion::Settings).to receive(:[]).with(:telemetry).and_return({})
      expect(described_class.configure_exporter).to be_nil
    end

    it 'handles missing otlp gem gracefully' do
      allow(Legion::Settings).to receive(:[]).with(:telemetry).and_return({ tracing: { exporter: :otlp } })
      allow(described_class).to receive(:require).with('opentelemetry-exporter-otlp').and_raise(LoadError)
      expect(described_class.configure_exporter).to be false
    end
  end

  describe '.tracing_settings' do
    before do
      allow(Legion::Settings).to receive(:[]).and_call_original
    end

    it 'returns tracing hash from settings' do
      allow(Legion::Settings).to receive(:[]).with(:telemetry).and_return({ tracing: { exporter: :otlp } })
      expect(described_class.tracing_settings).to eq({ exporter: :otlp })
    end

    it 'returns empty hash when telemetry not configured' do
      allow(Legion::Settings).to receive(:[]).with(:telemetry).and_return(nil)
      expect(described_class.tracing_settings).to eq({})
    end
  end
end
