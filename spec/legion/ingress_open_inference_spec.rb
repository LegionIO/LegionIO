# frozen_string_literal: true

require 'spec_helper'
require 'legion/ingress'

RSpec.describe 'Legion::Ingress OpenInference instrumentation' do
  before do
    stub_const('Legion::Telemetry::OpenInference', Module.new do
      def self.open_inference_enabled?
        true
      end

      def self.tool_span(**)
        yield(nil)
      end
    end)

    stub_const('Legion::Runner', Class.new do
      def self.run(**) = { success: true }
    end)

    stub_const('Legion::Events', Class.new do
      def self.emit(*) = nil
    end)
  end

  describe '.run' do
    it 'wraps runner invocation in tool_span' do
      expect(Legion::Telemetry::OpenInference).to receive(:tool_span)
        .with(hash_including(name: 'TestRunner.func'))
        .and_yield(nil)

      Legion::Ingress.run(
        payload:      {},
        runner_class: 'TestRunner',
        function:     'func',
        source:       'test'
      )
    end

    it 'works without OpenInference loaded' do
      hide_const('Legion::Telemetry::OpenInference')
      result = Legion::Ingress.run(
        payload:      {},
        runner_class: 'TestRunner',
        function:     'func',
        source:       'test'
      )
      expect(result[:success]).to be true
    end
  end
end
