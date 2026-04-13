# frozen_string_literal: true

require 'spec_helper'
require 'legion/runner'

module TestRunners
  module CheckSubtaskTest
    def self.do_work(**_args)
      { result: 'done' }
    end
  end
end

RSpec.describe 'Runner.run CheckSubtask forwarding' do
  before do
    stub_const('Legion::Exception::HandledTask', Class.new(StandardError)) unless defined?(Legion::Exception::HandledTask)
    allow(Legion::Events).to receive(:emit)
    allow(Legion::Runner::Status).to receive(:generate_task_id).and_return({ task_id: 42 })
    allow(Legion::Runner::Status).to receive(:update)
  end

  # When args: is provided explicitly, args != opts (no aliasing), so task_id/master_id
  # must be forwarded explicitly to CheckSubtask.new — they won't appear via **opts.
  describe 'explicit args: path — task_id and master_id must be forwarded' do
    let(:check_subtask_dbl) { double('check_subtask', publish: nil) }

    before do
      allow(Legion::Transport::Messages::CheckSubtask).to receive(:new).and_return(check_subtask_dbl)
    end

    it 'forwards task_id explicitly when args: is provided' do
      Legion::Runner.run(
        runner_class: TestRunners::CheckSubtaskTest,
        function: :do_work,
        task_id: 99,
        args: { some_param: 'value' },
        check_subtask: true
      )
      expect(Legion::Transport::Messages::CheckSubtask).to have_received(:new).with(
        hash_including(task_id: 99)
      )
    end

    it 'forwards master_id explicitly when args: is provided' do
      Legion::Runner.run(
        runner_class: TestRunners::CheckSubtaskTest,
        function: :do_work,
        task_id: 99,
        master_id: 7,
        args: { some_param: 'value' },
        check_subtask: true
      )
      expect(Legion::Transport::Messages::CheckSubtask).to have_received(:new).with(
        hash_including(master_id: 7)
      )
    end

    it 'forwards both task_id and master_id when args: is provided' do
      Legion::Runner.run(
        runner_class: TestRunners::CheckSubtaskTest,
        function: :do_work,
        task_id: 55,
        master_id: 3,
        args: { payload: 'data' },
        check_subtask: true
      )
      expect(Legion::Transport::Messages::CheckSubtask).to have_received(:new).with(
        hash_including(task_id: 55, master_id: 3)
      )
    end
  end
end
