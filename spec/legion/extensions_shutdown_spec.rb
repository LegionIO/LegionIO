# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions, '.shutdown' do
  let(:first) { double('first actor', cancel: true, await_stopped: true, close: true) }
  let(:second) { double('second actor', cancel: true, await_stopped: true, close: true) }
  let(:instances) { Concurrent::Array.new([first, second]) }

  before do
    keys = %i[@loaded_extensions @running_instances @subscription_pool]
    @previous = keys.to_h { |key| [key, described_class.instance_variable_get(key)] }
    described_class.instance_variable_set(:@loaded_extensions, [])
    described_class.instance_variable_set(:@running_instances, instances)
    described_class.instance_variable_set(:@subscription_pool, nil)
  end

  after do
    @previous.each { |key, value| described_class.instance_variable_set(key, value) }
  end

  before do
    allow(described_class).to receive(:transition_loaded_extensions)
  end

  it 'requests stop for every actor before waiting on the first' do
    entered = Concurrent::Event.new
    release = Concurrent::Event.new
    allow(first).to receive(:await_stopped) do
      entered.set
      release.wait
      true
    end
    thread = Thread.new { described_class.shutdown }
    expect(entered.wait(2)).to be true
    expect(first).to have_received(:cancel)
    expect(second).to have_received(:cancel)
    expect(first).not_to have_received(:close)
    expect(described_class).not_to have_received(:transition_loaded_extensions)

    release.set
    expect(thread.value).to be true
    expect(first).to have_received(:close)
    expect(second).to have_received(:close)
    expect(instances).to be_empty
  ensure
    release&.set
    thread&.join(2)
  end

  it 'preserves all actors and their resources when a shared deadline expires' do
    deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    allow(first).to receive(:await_stopped).with(deadline: deadline).and_return(false)

    expect(described_class.shutdown(deadline: deadline)).to be false

    expect(first).not_to have_received(:close)
    expect(second).not_to have_received(:close)
    expect(instances).to eq([first, second])
    expect(described_class).not_to have_received(:transition_loaded_extensions)
  end

  it 'does not declare success or clear handles after a cancellation error' do
    allow(first).to receive(:await_stopped).and_raise(IOError, 'cancel failed')
    allow(described_class).to receive(:handle_exception)

    expect { described_class.shutdown }.to raise_error(IOError, 'cancel failed')

    expect(instances).to eq([first, second])
    expect(first).not_to have_received(:close)
  end

  it 'retains actors when local dispatch still has an accepted job' do
    entered = Concurrent::Event.new
    release = Concurrent::Event.new
    Legion::Dispatch.reset!
    Legion::Dispatch.submit do
      entered.set
      release.wait
    end
    expect(entered.wait(2)).to be true

    expect(described_class.shutdown(deadline: ::Process.clock_gettime(::Process::CLOCK_MONOTONIC))).to be false
    expect(first).not_to have_received(:close)
    expect(instances).to eq([first, second])

    release.set
    expect(described_class.shutdown).to be true
  ensure
    release&.set
    Legion::Dispatch.reset!
  end
end
