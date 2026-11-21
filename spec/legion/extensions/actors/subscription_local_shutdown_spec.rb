# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/subscription'
require 'legion/transport/in_process'

RSpec.describe Legion::Extensions::Actors::Subscription, 'local shutdown' do
  it 'finishes the active local delivery before cancellation completes' do
    session = Legion::Transport::InProcess::Session.new.start
    channel = session.create_channel
    queue = Legion::Transport::InProcess::Queue.new(channel, 'shutdown.local')
    actor = described_class.allocate
    actor.instance_variable_set(:@queue, queue)
    entered = Concurrent::Event.new
    release = Concurrent::Event.new
    received = Queue.new
    runner = double('runner')
    allow(runner).to receive(:insert) do |**message|
      received << message
      entered.set
      release.wait
    end
    allow(actor).to receive_messages(lex_name: 'test', runner_name: 'insert', runner_class: runner,
                                     use_runner?: false, delay_start: 0)
    allow(actor).to receive(:find_function).and_return(:insert)
    allow(actor).to receive(:check_region_affinity).and_return(:local)
    allow(Legion::Transport::Connection).to receive(:lite_mode?).and_return(true)
    actor.subscribe

    producer = Thread.new do
      channel.default_exchange.publish(Legion::JSON.dump({ value: 'test' }), routing_key: queue.name,
                                       content_type: 'application/json', headers: { 'custom' => 'metadata' })
    end
    expect(entered.wait(2)).to be true
    actor.cancel
    expect(actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC))).to be false
    expect(channel.open?).to be true

    release.set
    expect(actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)).to be true
    producer.join(2)
    actor.close
    expect(received.pop).to include(value: 'test', custom: 'metadata', routing_key: queue.name)
    expect(Legion::Transport::Local.queue_depth(queue.name)).to eq(0)
  ensure
    release&.set
    producer&.join(2)
    actor&.cancel
    actor&.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)
    session&.close
  end
end
