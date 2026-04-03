# frozen_string_literal: true

require 'spec_helper'
require 'legion/task_outcome_observer'

RSpec.describe Legion::TaskOutcomeObserver do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
    # Clear event handlers between tests
    Legion::Events.instance_variable_set(:@listeners, Hash.new { |h, k| h[k] = [] })
  end

  describe '.setup' do
    it 'registers event handlers for task.completed and task.failed' do
      described_class.setup
      listeners = Legion::Events.instance_variable_get(:@listeners)
      expect(listeners['task.completed']).not_to be_empty
      expect(listeners['task.failed']).not_to be_empty
    end
  end

  describe '.enabled?' do
    it 'returns true by default' do
      allow(Legion::Settings).to receive(:dig).with(:task_outcome_observer).and_return(nil)
      expect(described_class.enabled?).to be true
    end

    it 'returns false when disabled in settings' do
      allow(Legion::Settings).to receive(:[]).with(:task_outcome_observer).and_return({ enabled: false })
      expect(described_class.enabled?).to be false
    end
  end

  describe 'event handling' do
    before { described_class.setup }

    it 'handles task.completed events' do
      payload = { task_id: 'abc', runner_class: 'Legion::Extensions::Node::Runners::Node', function: 'heartbeat' }
      expect { Legion::Events.emit('task.completed', **payload) }.not_to raise_error
    end

    it 'handles task.failed events' do
      payload = { task_id: 'def', runner_class: 'Legion::Extensions::Github::Runners::Issues', function: 'create' }
      expect { Legion::Events.emit('task.failed', **payload) }.not_to raise_error
    end
  end

  describe '.derive_domain' do
    it 'extracts snake_case domain from class name' do
      expect(described_class.send(:derive_domain, 'Legion::Extensions::Node::Runners::Node')).to eq('node')
    end

    it 'handles camelCase runner names' do
      expect(described_class.send(:derive_domain, 'Legion::Extensions::Github::Runners::PullRequests')).to eq('pull_requests')
    end
  end

  describe '.record_learning' do
    it 'does not raise when MetaLearning is not defined' do
      expect { described_class.send(:record_learning, domain: 'test', success: true) }.not_to raise_error
    end

    it 'uses the meta learning client when available' do
      client = instance_double('meta_client', create_learning_domain: { id: 'dom-123' }, record_learning_episode: true)
      client_class = Class.new
      allow(client_class).to receive(:new).and_return(client)
      stub_const('Legion::Extensions::Agentic::Learning::MetaLearning::Client', client_class)

      described_class.send(:record_learning, domain: 'test', success: true)

      expect(client).to have_received(:create_learning_domain).with(name: 'test')
      expect(client).to have_received(:record_learning_episode).with(domain_id: 'dom-123', success: true)
    end
  end

  describe '.publish_lesson' do
    it 'does not raise when Apollo is not defined' do
      hide_const('Legion::Apollo') if defined?(Legion::Apollo)
      expect do
        described_class.send(:publish_lesson, runner: 'Test', function: 'run', success: true)
      end.not_to raise_error
    end

    it 'calls Apollo.ingest when available' do
      stub_const('Legion::Apollo', Module.new do
        def self.respond_to?(name, *)
          name == :ingest ? true : super
        end

        def self.ingest(**) = nil
      end)

      expect(Legion::Apollo).to receive(:ingest).with(hash_including(
                                                        knowledge_domain: 'operational',
                                                        source_agent:     'system:task_observer'
                                                      ))
      described_class.send(:publish_lesson, runner: 'Test::Runners::Foo', function: 'bar', success: true)
    end
  end

  describe '.setup_llm_reflection_hook' do
    it 'does not raise when LLM is not defined' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      expect { described_class.send(:setup_llm_reflection_hook) }.not_to raise_error
    end
  end
end
