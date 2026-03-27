# frozen_string_literal: true

require 'spec_helper'
require 'legion/dispatch'

RSpec.describe Legion::Dispatch do
  describe '.dispatcher' do
    before { described_class.reset! }

    after { described_class.shutdown }

    it 'returns a Local dispatcher by default' do
      expect(described_class.dispatcher).to be_a(Legion::Dispatch::Local)
    end

    it 'memoizes the dispatcher instance' do
      expect(described_class.dispatcher).to be(described_class.dispatcher)
    end
  end

  describe '.submit' do
    before { described_class.reset! }

    after { described_class.shutdown }

    it 'delegates to the dispatcher' do
      result = Concurrent::IVar.new
      described_class.submit { result.set(:dispatched) }
      expect(result.value(5)).to eq(:dispatched)
    end
  end

  describe '.shutdown' do
    before { described_class.reset! }

    it 'stops the dispatcher' do
      described_class.dispatcher # ensure initialized
      described_class.shutdown
      expect(described_class.dispatcher.capacity[:running]).to be false
    end
  end

  describe '.reset!' do
    it 'clears the memoized dispatcher' do
      described_class.reset!
      d1 = described_class.dispatcher
      described_class.shutdown
      described_class.reset!
      d2 = described_class.dispatcher
      expect(d1).not_to be(d2)
      described_class.shutdown
    end
  end
end
