# frozen_string_literal: true

require 'spec_helper'
require 'legion/ingress'
require 'legion/extensions'
require 'legion/rbac'

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
    around do |example|
      original_settings = Legion::Settings[:rbac]
      original_roles = Legion::Rbac.instance_variable_get(:@role_index)
      Legion::Settings.loader.settings[:rbac] = Legion::Rbac::Settings.default
      Legion::Rbac.setup
      example.run
    ensure
      Legion::Settings.loader.settings[:rbac] = original_settings
      Legion::Rbac.instance_variable_set(:@role_index, original_roles)
    end

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
        payload:      { key: 'value' },
        runner_class: 'TestLocalRunner',
        function:     'action',
        principal:    Legion::Rbac::Principal.new(id: 'local-test', roles: ['worker']),
        source:       'test'
      )
      expect(result[:result]).to eq('local')
    end
  end
end
