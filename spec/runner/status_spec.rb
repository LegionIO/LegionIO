# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner/status'

RSpec.describe Legion::Runner::Status do
  around do |example|
    original = Legion::Settings[:data]
    Legion::Settings.loader.settings[:data] = { connected: false }
    example.run
  ensure
    Legion::Settings.loader.settings[:data] = original
  end

  it 'does not invent durable task identities without connected storage' do
    expect(described_class.generate_task_id(runner_class: 'MissingRunner', function: 'run')).to be_nil
  end

  it 'rejects incomplete updates before publishing a misleading lifecycle event' do
    expect(Legion::Transport::Messages::TaskUpdate).not_to receive(:new)
    expect { described_class.update(task_id: nil, status: 'task.failed') }.to raise_error(ArgumentError)
  end
end
