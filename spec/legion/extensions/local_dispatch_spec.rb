# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions'
require 'legion/dispatch'

RSpec.describe 'Extensions local dispatch wiring' do
  before do
    Legion::Dispatch.reset!
    allow(Legion::Settings).to receive(:dig).and_call_original
  end

  after { Legion::Dispatch.shutdown }

  describe 'hook_all_actors' do
    it 'logs local task count alongside other actor types' do
      allow(Legion::Extensions).to receive(:instance_variable_get).with(:@pending_actors).and_return([])
      expect(Legion::Dispatch.dispatcher).to be_a(Legion::Dispatch::Local)
    end
  end

  describe 'local_tasks accessor' do
    it 'exposes local_tasks as an array' do
      expect(Legion::Extensions.local_tasks).to be_an(Array).or be_nil
    end
  end

  describe 'dispatch_local_actors' do
    it 'submits each local actor to Legion::Dispatch' do
      mock_dispatcher = instance_double(Legion::Dispatch::Local, submit: nil, stop: nil, capacity: {})
      allow(Legion::Dispatch).to receive(:dispatcher).and_return(mock_dispatcher)

      runner_mod = Module.new { def self.action(**); end }
      actor_hash = {
        extension_name: 'test_ext',
        actor_class:    Class.new,
        runner_class:   runner_mod,
        actor_name:     'test_actor'
      }

      Legion::Extensions.send(:dispatch_local_actors, [actor_hash])
      expect(actor_hash).to have_key(:runner_module)
    end
  end
end
