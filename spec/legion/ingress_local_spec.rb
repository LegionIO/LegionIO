# frozen_string_literal: true

require 'spec_helper'
require 'legion/ingress'
require 'legion/extensions'

RSpec.describe 'Ingress local dispatch' do
  let(:runner_module) do
    Module.new do
      def self.action(**args)
        { result: 'local', **args }
      end
    end
  end

  describe '.local_runner?' do
    it 'returns true when runner is in local_tasks' do
      allow(Legion::Extensions).to receive(:local_tasks).and_return([
                                                                       { runner_module: runner_module, actor_name: 'test' }
                                                                     ])
      expect(Legion::Ingress.local_runner?(runner_module)).to be true
    end

    it 'returns false when runner is not in local_tasks' do
      allow(Legion::Extensions).to receive(:local_tasks).and_return([])
      expect(Legion::Ingress.local_runner?(runner_module)).to be false
    end

    it 'returns false when Extensions is not set up' do
      allow(Legion::Extensions).to receive(:local_tasks).and_return(nil)
      expect(Legion::Ingress.local_runner?(runner_module)).to be false
    end
  end

  describe '.run with local runner' do
    before do
      allow(Legion::Extensions).to receive(:local_tasks).and_return([
                                                                       { runner_module: runner_module, actor_name: 'test' }
                                                                     ])
    end

    it 'invokes the runner directly without AMQP' do
      # Use a named constant so Ingress validation and const_get work
      stub_const('TestLocalRunner', runner_module)
      allow(Legion::Extensions).to receive(:local_tasks).and_return([
                                                                       { runner_module: TestLocalRunner, actor_name: 'test' }
                                                                     ])

      result = Legion::Ingress.run(
        payload: { key: 'value' },
        runner_class: 'TestLocalRunner',
        function: 'action',
        source: 'test'
      )
      expect(result[:result]).to eq('local')
    end
  end
end
