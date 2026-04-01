# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/team_memory'

RSpec.describe Legion::CLI::Chat::TeamMemory do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:debug)
    allow(Legion::Logging).to receive(:warn)
  end

  describe '.enabled?' do
    it 'returns false by default' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it 'returns true when enabled in settings' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: true })
      expect(described_class.enabled?).to be true
    end
  end

  describe '.sync_add' do
    it 'does nothing when disabled' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: false })
      expect { described_class.sync_add('test entry') }.not_to raise_error
    end

    it 'does nothing when Apollo is not available' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: true })
      hide_const('Legion::Apollo') if defined?(Legion::Apollo)
      expect { described_class.sync_add('test entry') }.not_to raise_error
    end

    it 'calls Apollo.ingest when enabled and available' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: true })
      allow(described_class).to receive(:git_remote_url).and_return('git@github.com:LegionIO/LegionIO.git')

      stub_const('Legion::Apollo', Module.new do
        def self.respond_to?(name, *)
          %i[ingest retrieve].include?(name) || super
        end

        def self.ingest(**) = nil
      end)

      expect(Legion::Apollo).to receive(:ingest).with(hash_including(
                                                        tags:             ['team_memory', 'repo:git@github.com:LegionIO/LegionIO.git'],
                                                        knowledge_domain: 'team_memory'
                                                      ))
      described_class.sync_add('user prefers concise output')
    end
  end

  describe '.retrieve' do
    it 'returns empty array when disabled' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: false })
      expect(described_class.retrieve).to eq([])
    end

    it 'returns empty array when Apollo is not available' do
      allow(Legion::Settings).to receive(:dig).with(:memory, :team_sync).and_return({ enabled: true })
      hide_const('Legion::Apollo') if defined?(Legion::Apollo)
      expect(described_class.retrieve).to eq([])
    end
  end

  describe '.load_context' do
    it 'returns nil when no team entries' do
      allow(described_class).to receive(:retrieve).and_return([])
      expect(described_class.load_context).to be_nil
    end

    it 'formats entries as markdown' do
      allow(described_class).to receive(:retrieve).and_return(['entry one', 'entry two'])
      context = described_class.load_context
      expect(context).to include('## Team Memory')
      expect(context).to include('- entry one')
      expect(context).to include('- entry two')
    end
  end
end
