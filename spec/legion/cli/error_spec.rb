# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/error'

RSpec.describe Legion::CLI::Error do
  describe '.actionable' do
    subject(:error) do
      described_class.actionable(
        code:        :transport_unavailable,
        message:     'Cannot connect to RabbitMQ',
        suggestions: ['Run legion doctor', 'Check transport settings']
      )
    end

    it 'returns a Legion::CLI::Error instance' do
      expect(error).to be_a(described_class)
    end

    it 'sets the message' do
      expect(error.message).to eq('Cannot connect to RabbitMQ')
    end

    it 'sets the code' do
      expect(error.code).to eq(:transport_unavailable)
    end

    it 'sets suggestions' do
      expect(error.suggestions).to eq(['Run legion doctor', 'Check transport settings'])
    end
  end

  describe '#actionable?' do
    it 'returns true when suggestions are present' do
      error = described_class.actionable(code: :foo, message: 'msg', suggestions: ['do this'])
      expect(error.actionable?).to be(true)
    end

    it 'returns false when suggestions are empty' do
      error = described_class.actionable(code: :foo, message: 'msg', suggestions: [])
      expect(error.actionable?).to be(false)
    end

    it 'returns false when suggestions are nil' do
      error = described_class.new('plain error')
      expect(error.actionable?).to be(false)
    end
  end

  describe '#code' do
    it 'returns nil on a plain error' do
      error = described_class.new('plain error')
      expect(error.code).to be_nil
    end

    it 'returns the code set via .actionable' do
      error = described_class.actionable(code: :permission_denied, message: 'msg')
      expect(error.code).to eq(:permission_denied)
    end
  end
end
