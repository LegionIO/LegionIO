# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/subagent'

RSpec.describe Legion::CLI::Chat::Subagent do
  before do
    described_class.configure(max_concurrency: 3)
  end

  describe '.configure' do
    it 'sets max concurrency' do
      described_class.configure(max_concurrency: 5)
      expect(described_class.max_concurrency).to eq(5)
    end
  end

  describe '.spawn' do
    it 'returns agent info on success' do
      allow(Open3).to receive(:capture3).and_return(['output', '', double(exitstatus: 0)])

      result = described_class.spawn(task: 'test task')

      expect(result[:id]).to match(/^agent-/)
      expect(result[:status]).to eq('running')
      expect(result[:task]).to eq('test task')
      sleep 0.1 # Let thread finish
    end

    it 'returns error when at capacity' do
      described_class.configure(max_concurrency: 0)
      result = described_class.spawn(task: 'test')
      expect(result[:error]).to include('Max concurrency')
    end

    it 'calls on_complete callback when done' do
      allow(Open3).to receive(:capture3).and_return(['done', '', double(exitstatus: 0)])
      completed = false

      described_class.spawn(
        task:        'test',
        on_complete: ->(_id, _result) { completed = true }
      )

      sleep 0.5
      expect(completed).to be true
    end
  end

  describe '.running' do
    it 'returns empty array when no agents running' do
      expect(described_class.running).to eq([])
    end
  end

  describe '.running_count' do
    it 'returns 0 when no agents running' do
      expect(described_class.running_count).to eq(0)
    end
  end

  describe '.at_capacity?' do
    it 'returns false when under limit' do
      expect(described_class.at_capacity?).to be false
    end

    it 'returns true when at limit' do
      described_class.configure(max_concurrency: 0)
      expect(described_class.at_capacity?).to be true
    end
  end

  describe '.configure_from_settings' do
    before do
      allow(Legion::Settings).to receive(:dig).and_return(nil)
    end

    it 'reads max_concurrency from settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :subagent, :max_concurrency).and_return(7)
      described_class.configure_from_settings
      expect(described_class.max_concurrency).to eq(7)
    end

    it 'reads timeout from settings' do
      allow(Legion::Settings).to receive(:dig).with(:chat, :subagent, :timeout).and_return(600)
      described_class.configure_from_settings
      expect(described_class.timeout).to eq(600)
    end

    it 'falls back to defaults when settings unavailable' do
      described_class.configure_from_settings
      expect(described_class.max_concurrency).to eq(3)
      expect(described_class.timeout).to eq(300)
    end
  end
end
