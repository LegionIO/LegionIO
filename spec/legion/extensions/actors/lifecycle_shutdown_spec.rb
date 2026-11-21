# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/every'
require 'legion/extensions/actors/poll'
require 'legion/extensions/actors/once'
require 'legion/extensions/actors/loop'

module LifecycleShutdownFixtures
  class Loop < Legion::Extensions::Actors::Loop
    def initialize(started:, release:, calls:, **)
      @started = started
      @release = release
      @calls = calls
      super()
    end

    def action(**)
      @calls.increment
      @started.set
      @release.wait
    end
  end
end

RSpec.describe 'Actor execution drain' do
  let(:started) { Concurrent::Event.new }
  let(:release) { Concurrent::Event.new }
  let(:calls) { Concurrent::AtomicFixnum.new }

  after do
    release.set
    @actor&.cancel
    @actor&.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)
  end

  [Legion::Extensions::Actors::Every, Legion::Extensions::Actors::Poll].each do |actor_type|
    it "waits for an executing #{actor_type.name.split('::').last} invocation" do
      callback = nil
      timer = double('timer', execute: true, shutdown: true)
      allow(Concurrent::TimerTask).to receive(:new) { |**_options, &block|
        callback = block
        timer
      }
      @actor = actor_type.new
      allow(@actor).to receive(:skip_or_run) do
        calls.increment
        started.set
        release.wait
      end
      thread = Thread.new { callback.call }
      expect(started.wait(2)).to be true

      @actor.cancel
      expect(@actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC))).to be false
      release.set
      thread.join(2)
      expect(@actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)).to be true
      callback.call
      expect(calls.value).to eq(1)
    ensure
      release.set
      thread&.join(2)
    end
  end

  it 'prevents a delayed Every start from restarting its timer after cancellation' do
    callback = nil
    timer = double('timer', execute: true, shutdown: true)
    delayed = double('delayed start', cancel: true)
    allow(Concurrent::TimerTask).to receive(:new).and_return(timer)
    allow(Concurrent::ScheduledTask).to receive(:execute) { |*, &block|
      callback = block
      delayed
    }
    @actor = Legion::Extensions::Actors::Every.allocate
    allow(@actor).to receive(:delay).and_return(10)
    @actor.send(:initialize)

    @actor.cancel
    callback.call

    expect(timer).not_to have_received(:execute)
    expect(delayed).to have_received(:cancel)
  end

  it 'cancels every pending Once task and prevents a late callback from invoking its runner' do
    callbacks = []
    tasks = []
    allow(Concurrent::ScheduledTask).to receive(:execute) do |*, &block|
      callbacks << block
      double('scheduled task', cancel: true).tap { |task| tasks << task }
    end
    @actor = Legion::Extensions::Actors::Once.allocate
    allow(@actor).to receive(:functions).and_return(%i[first second])
    allow(@actor).to receive(:runner) { calls.increment }
    @actor.send(:initialize)

    @actor.cancel
    callbacks.each(&:call)

    expect(tasks.size).to eq(2)
    tasks.each { |task| expect(task).to have_received(:cancel) }
    expect(calls.value).to eq(0)
  end

  it 'waits for the final Loop iteration and its execution future' do
    @actor = LifecycleShutdownFixtures::Loop.new(started: started, release: release, calls: calls)
    expect(started.wait(2)).to be true

    @actor.cancel
    expect(@actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC))).to be false
    release.set

    expect(@actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)).to be true
    expect(calls.value).to eq(1)
  end
end
