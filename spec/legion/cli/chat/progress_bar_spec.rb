# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/progress_bar'

RSpec.describe Legion::CLI::Chat::ProgressBar do
  let(:output) { StringIO.new }
  let(:bar) { described_class.new(total: 10, label: 'Test', output: output) }

  describe '#advance' do
    it 'increments current' do
      bar.advance(3)
      expect(bar.current).to eq(3)
    end

    it 'caps at total' do
      bar.advance(20)
      expect(bar.current).to eq(10)
    end

    it 'renders to output' do
      bar.advance(5)
      expect(output.string).to include('50.0%')
    end
  end

  describe '#percentage' do
    it 'calculates correctly' do
      bar.advance(5)
      expect(bar.percentage).to eq(50.0)
    end

    it 'starts at zero' do
      expect(bar.percentage).to eq(0.0)
    end
  end

  describe '#finish' do
    it 'sets current to total' do
      bar.finish
      expect(bar.current).to eq(10)
      expect(bar.percentage).to eq(100.0)
    end
  end

  describe '#eta' do
    it 'returns 0 when complete' do
      bar.finish
      expect(bar.eta).to eq(0)
    end

    it 'returns 0 when no progress' do
      expect(bar.eta).to eq(0)
    end
  end

  describe '#elapsed' do
    it 'returns non-negative duration' do
      expect(bar.elapsed).to be >= 0
    end
  end
end
