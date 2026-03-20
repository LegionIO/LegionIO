# frozen_string_literal: true

require 'spec_helper'
require 'legion/service'
require 'legion/telemetry/safety_metrics'

RSpec.describe Legion::Service do
  describe '#setup_safety_metrics' do
    let(:service) { described_class.allocate }

    it 'calls SafetyMetrics.start' do
      expect(Legion::Telemetry::SafetyMetrics).to receive(:start)
      service.send(:setup_safety_metrics)
    end

    it 'rescues LoadError gracefully' do
      allow(service).to receive(:require_relative).and_raise(LoadError)
      expect { service.send(:setup_safety_metrics) }.not_to raise_error
    end
  end
end
