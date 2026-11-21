# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/actors/subscription'
require 'bunny/consumer_work_pool'

RSpec.describe Legion::Extensions::Actors::Subscription, 'shutdown' do
  let(:actor) { described_class.allocate }
  let(:pool) { Bunny::ConsumerWorkPool.new(1, false, 0.05) }
  let(:started) { Concurrent::Event.new }
  let(:release) { Concurrent::Event.new }
  let(:cancelled) { Concurrent::Event.new }
  let(:events) { Queue.new }
  let(:channel) { double('channel', work_pool: pool, prefetch: nil, register_queue: nil, open?: true) }
  let(:queue) { double('queue', channel: channel, name: 'shutdown.test') }
  let(:consumer) { double('consumer') }
  let(:runner) { double('runner') }
  let(:delivery) { Struct.new(:delivery_tag, :routing_key).new(1, 'test.insert') }

  before do
    allow(actor).to receive_messages(queue: double(new: queue), lex_name: 'test', runner_name: 'insert',
                                     runner_class: runner, use_runner?: false, prefetch: 16)
    allow(actor).to receive(:create_dedicated_channel).and_return(channel)
    allow(actor).to receive(:process_message) { |payload, *| payload }
    allow(actor).to receive(:find_function).and_return(:insert)
    allow(actor).to receive(:check_region_affinity).and_return(:local)
    allow(Legion::Transport::Connection).to receive(:lite_mode?).and_return(false)
    allow(Bunny::Consumer).to receive(:new).and_return(consumer)
    allow(consumer).to receive(:on_delivery) { |&callback| @delivery_callback = callback }
    allow(consumer).to receive(:cancel) do
      cancelled.set
      pool.shutdown(true)
    end
    allow(queue).to receive(:acknowledge) do |tag|
      raise IOError, 'acknowledging a closed channel' unless channel.open?

      events << [:ack, tag]
    end
    allow(channel).to receive(:close) do
      allow(channel).to receive(:open?).and_return(false)
      events << :closed
    end
    allow(actor).to receive(:handle_exception)
    actor.prepare
    pool.start
  end

  after do
    release.set
    actor.cancel
    actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)
    pool.threads.each { |thread| thread.join(2) }
  end

  def deliver(tag:, **message)
    info = Struct.new(:delivery_tag, :routing_key).new(tag, 'test.insert')
    pool.submit { @delivery_callback.call(info, nil, message) }
  end

  it 'keeps the channel open until both the active and buffered deliveries acknowledge' do
    allow(runner).to receive(:insert) do |**message|
      if message[:hold]
        started.set
        release.wait
      end
    end
    deliver(tag: 1, hold: true)
    expect(started.wait(2)).to be true
    deliver(tag: 2)

    actor.cancel
    expect(cancelled.wait(2)).to be true
    expect(actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 0.1)).to be false
    expect(channel).not_to have_received(:close)
    expect { actor.close }.to raise_error(ThreadError, /have not stopped/)

    release.set
    expect(actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)).to be true
    actor.close

    expect(3.times.map { events.pop }).to eq([[:ack, 1], [:ack, 2], :closed])
    expect(actor).not_to have_received(:handle_exception)
  end

  it 'requests consumer cancellation only once under concurrent stop requests' do
    requests = Array.new(8) { Thread.new { actor.cancel } }
    requests.each(&:join)

    expect(actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)).to be true
    actor.close
    actor.close

    expect(consumer).to have_received(:cancel).once
    expect(channel).to have_received(:close).once
  end

  it 'does not cancel from a callback when the process shutdown flag is set' do
    client = Legion::Settings[:client]
    original = client[:shutting_down]
    begin
      client[:shutting_down] = true
      allow(runner).to receive(:insert)

      @delivery_callback.call(delivery, nil, {})

      expect(consumer).not_to have_received(:cancel)
      expect(channel).not_to have_received(:close)
      expect(events.pop).to eq([:ack, 1])
    ensure
      client[:shutting_down] = original
    end
  end

  it 'retains a failed cancellation instead of declaring the subscription drained' do
    allow(consumer).to receive(:cancel).and_raise(IOError, 'cancel failed')

    actor.cancel

    expect do
      actor.await_stopped(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + 2)
    end.to raise_error(IOError, 'cancel failed')
    expect(channel).not_to have_received(:close)
    expect(actor).to have_received(:handle_exception).with(instance_of(IOError), level: :error, operation: :subscription_cancel)
  ensure
    pool.shutdown
    actor.instance_variable_set(:@cancel_error, nil)
  end

  it 'does not republish a completed invocation when its original channel cannot acknowledge' do
    allow(runner).to receive(:insert)
    error = Bunny::ChannelAlreadyClosed.new('closed during acknowledgement', channel)
    allow(queue).to receive(:acknowledge).and_raise(error)
    expect(actor).not_to receive(:reject_or_retry)

    @delivery_callback.call(delivery, nil, {})

    expect(runner).to have_received(:insert).once
    expect(actor).to have_received(:handle_exception).with(error, level: :error, operation: :subscription_settlement)
  end
end
