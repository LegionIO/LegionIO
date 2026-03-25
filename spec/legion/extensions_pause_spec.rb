# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions do
  describe '.pause_actors' do
    before do
      allow(Legion::Logging).to receive(:info)
      allow(Legion::Logging).to receive(:debug)
    end

    it 'shuts down all timer tasks on running instances' do
      timer1 = instance_double(Concurrent::TimerTask, shutdown: true)
      timer2 = instance_double(Concurrent::TimerTask, shutdown: true)

      inst1 = double('actor1')
      inst2 = double('actor2')
      allow(inst1).to receive(:instance_variable_get).with(:@timer).and_return(timer1)
      allow(inst2).to receive(:instance_variable_get).with(:@timer).and_return(timer2)

      described_class.instance_variable_set(:@running_instances, Concurrent::Array.new([inst1, inst2]))

      described_class.pause_actors

      expect(timer1).to have_received(:shutdown)
      expect(timer2).to have_received(:shutdown)
    end

    it 'skips instances without a timer' do
      inst = double('actor_no_timer')
      allow(inst).to receive(:instance_variable_get).with(:@timer).and_return(nil)

      described_class.instance_variable_set(:@running_instances, Concurrent::Array.new([inst]))

      expect { described_class.pause_actors }.not_to raise_error
    end

    it 'does not raise when running_instances is nil' do
      described_class.instance_variable_set(:@running_instances, nil)

      expect { described_class.pause_actors }.not_to raise_error
    end

    it 'rescues errors from individual actors' do
      inst = double('bad_actor')
      allow(inst).to receive(:instance_variable_get).with(:@timer).and_raise(StandardError, 'oops')

      described_class.instance_variable_set(:@running_instances, Concurrent::Array.new([inst]))

      expect { described_class.pause_actors }.not_to raise_error
    end

    it 'logs that actors were paused' do
      described_class.instance_variable_set(:@running_instances, Concurrent::Array.new)

      described_class.pause_actors

      expect(Legion::Logging).to have_received(:info).with('All actors paused')
    end
  end
end
