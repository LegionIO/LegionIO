# frozen_string_literal: true

require 'spec_helper'
require 'legion/task_outcome_observer'

RSpec.describe Legion::TaskOutcomeObserver do
  let(:episodes) { [] }
  let(:lessons) { [] }
  let(:payload) do
    { task_id: 42, runner_class: 'Legion::Extensions::Github::Runners::Issues', function: 'create',
      persisted: true, success: true, status: 'task.completed' }
  end

  around do |example|
    original_listeners = Legion::Events.instance_variable_get(:@listeners)
    original_settings = Legion::Settings[:task_outcome_observer]
    Legion::Settings.loader.settings[:task_outcome_observer] = { enabled: true }
    Legion::Events.instance_variable_set(:@listeners, Hash.new { |hash, key| hash[key] = [] })
    described_class.instance_variable_set(:@meta_learning_client, nil)
    described_class.instance_variable_set(:@learning_domain_map, nil)
    example.run
  ensure
    Legion::Events.instance_variable_set(:@listeners, original_listeners)
    Legion::Settings.loader.settings[:task_outcome_observer] = original_settings
    described_class.instance_variable_set(:@meta_learning_client, nil)
    described_class.instance_variable_set(:@learning_domain_map, nil)
  end

  before do
    sink = episodes
    client = Class.new do
      define_method(:create_learning_domain) { |**| { id: 'issues' } }
      define_method(:record_learning_episode) { |**episode| sink << episode }
    end
    stub_const('Legion::Extensions::Agentic::Learning::MetaLearning::Client', client)
    lesson_sink = lessons
    apollo = Module.new
    apollo.define_singleton_method(:ingest) { |**lesson| lesson_sink << lesson }
    stub_const('Legion::Apollo', apollo)
    described_class.setup
  end

  it 'learns success only from a committed successful outcome' do
    Legion::Events.emit('task.completed', **payload)
    expect(episodes).to eq([{ domain_id: 'issues', success: true }])
    expect(lessons.first[:tags]).to include('succeeded')
  end

  it 'cannot learn success from a failure mislabeled as a completion event' do
    Legion::Events.emit('task.completed', **payload, success: false, status: 'task.failed')
    expect(episodes).to be_empty
    expect(lessons).to be_empty
  end

  it 'does not teach retries, unknown external effects, or ephemeral outcomes as terminal facts' do
    Legion::Events.emit('task.failed', **payload, success: false, status: 'task.retry_pending')
    Legion::Events.emit('task.failed', **payload, success: false, status: 'task.unknown')
    Legion::Events.emit('task.completed', **payload, persisted: false)
    expect(episodes).to be_empty
    expect(lessons).to be_empty
  end

  it 'learns a recorded terminal failure as failure' do
    Legion::Events.emit('task.failed', **payload, success: false, status: 'task.failed')
    expect(episodes).to eq([{ domain_id: 'issues', success: false }])
    expect(lessons.first[:tags]).to include('failed')
  end

  it 'honors the real settings overlay disabling observation' do
    Legion::Settings.loader.settings[:task_outcome_observer] = { enabled: false }
    expect(described_class.enabled?).to be false
  end
end
