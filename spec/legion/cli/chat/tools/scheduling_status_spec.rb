# frozen_string_literal: true

require 'spec_helper'
require 'ruby_llm'
require 'legion/cli/chat/tools/scheduling_status'

RSpec.describe Legion::CLI::Chat::Tools::SchedulingStatus do
  subject(:tool) { described_class.new }

  let(:scheduling_mod) do
    Module.new do
      def self.status
        {
          enabled:         true,
          peak_hours:      true,
          peak_range:      '14..22',
          next_off_peak:   '2026-03-23T23:00:00Z',
          defer_intents:   %i[batch background maintenance],
          max_defer_hours: 8
        }
      end
    end
  end

  let(:batch_mod) do
    Module.new do
      def self.status
        {
          enabled:        true,
          queue_size:     5,
          max_batch_size: 100,
          window_seconds: 300,
          oldest_queued:  '2026-03-23T12:00:00Z',
          by_priority:    { normal: 3, low: 2 }
        }
      end
    end
  end

  before do
    stub_const('Legion::LLM::Scheduling', scheduling_mod)
    stub_const('Legion::LLM::Batch', batch_mod)
  end

  describe '#execute' do
    it 'returns overview by default' do
      result = tool.execute
      expect(result).to include('Scheduling & Batch Overview')
      expect(result).to include('peak now')
      expect(result).to include('Queue Depth: 5')
    end

    it 'shows scheduling detail' do
      result = tool.execute(action: 'scheduling')
      expect(result).to include('Scheduling Detail')
      expect(result).to include('14..22')
      expect(result).to include('Max Defer Hours:  8')
      expect(result).to include('batch, background, maintenance')
    end

    it 'shows batch detail' do
      result = tool.execute(action: 'batch')
      expect(result).to include('Batch Queue Detail')
      expect(result).to include('Queue Size:     5')
      expect(result).to include('normal')
      expect(result).to include('low')
    end

    it 'handles missing scheduling module' do
      hide_const('Legion::LLM::Scheduling')
      result = tool.execute(action: 'scheduling')
      expect(result).to eq('Scheduling module not available.')
    end

    it 'handles missing batch module' do
      hide_const('Legion::LLM::Batch')
      result = tool.execute(action: 'batch')
      expect(result).to eq('Batch module not available.')
    end
  end
end
