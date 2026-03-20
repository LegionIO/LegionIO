# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Legion::Extensions::Actors::Subscription OpenInference' do
  let(:actor) { Legion::Extensions::Actors::Subscription.allocate }

  before do
    stub_const('Legion::Telemetry::OpenInference', Module.new do
      def self.open_inference_enabled?
        true
      end

      def self.chain_span(**)
        yield(nil)
      end
    end)
  end

  describe '#dispatch_with_chain_span' do
    it 'wraps runner dispatch in chain_span' do
      expect(Legion::Telemetry::OpenInference).to receive(:chain_span)
        .with(hash_including(type: 'task_chain'))
        .and_yield(nil)

      allow(Legion::Runner).to receive(:run).and_return({ success: true })

      actor.send(:dispatch_runner, { test: true }, 'TestRunner', 'func', true, true)
    end

    it 'works without OpenInference' do
      hide_const('Legion::Telemetry::OpenInference')
      allow(Legion::Runner).to receive(:run).and_return({ success: true })

      result = actor.send(:dispatch_runner, { test: true }, 'TestRunner', 'func', true, true)
      expect(result[:success]).to be true
    end
  end
end
